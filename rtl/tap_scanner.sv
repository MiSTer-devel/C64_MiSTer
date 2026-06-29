`timescale 1ns/1ps
// ============================================================================
// TAP scanner - builds an accurate counter -> TAP byte-offset map for FF/REW
//
// This module scans the TAP stream while it is being downloaded and converts the
// raw pulse durations into real elapsed tape time.  The generated time_map lets
// the top-level jump to the TAP byte offset corresponding to each absolute
// mechanical tape-counter step.
//
// Accuracy notes:
// - Supports TAP v0, v1 and v2 timing encodings.
// - Uses the same 1 MHz TAP pulse timebase as the existing c1530 player,
//   so the generated map stays aligned with the counter during playback.
// - v1/v2 long pulses are mapped back to the *start* of the 00 xx xx xx pulse
//   sequence, never into the middle of the 3-byte overflow value.  This is
//   important because playback can only safely resume at a valid TAP token.
// - No loader-specific assumptions are made; the map is based only on pulse
//   durations, so turbo loaders, custom loaders, long silences, and v2 halfwave
//   files are handled uniformly.
// ============================================================================

module tap_scanner #(
	parameter int THRESH_BASE  = 2693,     // ms/counter step at tape start
	parameter int THRESH_INC   = 6,        // added ms per counter step
	parameter int ABS_MAX      = 8191,     // max absolute counter index for 13-bit map
	parameter int MAP_AW       = 13        // 2^13 = 8192 entries
) (
	input        clk,
	input        reset_n,

	// ioctl TAP download stream
	input        start,          // pulse at beginning of TAP download
	input        tap_wr,         // ioctl_data valid for this byte
	input [24:0] tap_addr,       // byte offset in TAP file (including 20-byte header)
	input  [7:0] tap_data,
	input        tap_done,       // pulse at end of TAP download

	// time_map write port
	output reg                  map_wr,
	output reg [MAP_AW-1:0]     map_addr,
	output reg [24:0]           map_data,  // safe TAP byte offset to resume from

	// status
	output reg                  busy,
	output reg                  ready,
	output reg [MAP_AW-1:0]     map_max,

	// Asserted while the scanner is catching up writing map entries.  The top
	// level must OR this into ioctl_wait for TAP downloads, otherwise bytes can
	// arrive while ST_WRITE_MAP is emitting multiple counter boundaries.
	output                       wait_req
);

// ---------------------------------------------------------------------------
// Playback timing.
// c1530 advances TAP pulse counters once per 32 MHz / 32 tick, so one TAP
// cycle is treated as 1 us by the existing player.  The FF/REW map must use
// the same timebase or counter positions will drift from real playback.
// ---------------------------------------------------------------------------
localparam int TAP_PLAYER_Q10 = 1_024_000; // 1000 cycles/ms in Q10

// TAP header fields used by the scanner.
reg [1:0] tap_version;

// Accumulators and mechanical-counter model
reg [MAP_AW-1:0] count;
reg [47:0] time_acc_cycles;
reg [47:0] target_cycles;
reg [15:0] threshold_ms;
reg [31:0] cycles_per_ms_q10;

// Last decoded pulse span. Map entries are written to the nearest safe TAP
// token boundary (start or next token), which greatly improves seeks across
// very long pulses/silence while never resuming inside a multi-byte token.
reg [47:0] pulse_start_cycles;
reg [24:0] pulse_start_offset;
reg [24:0] pulse_end_offset;

// v1/v2 overflow-token state. A long pulse is encoded as 00 + 24-bit cycles.
reg [1:0]  ovf_bytes_left;
reg [23:0] ovf_duration;
reg [24:0] ovf_start_offset;

reg done_pending;

localparam [2:0] ST_IDLE      = 3'd0;
localparam [2:0] ST_HEADER    = 3'd1;
localparam [2:0] ST_DATA      = 3'd2;
localparam [2:0] ST_WRITE_MAP = 3'd3;
localparam [2:0] ST_DONE      = 3'd4;
reg [2:0] state;

function automatic [47:0] ms_to_cycles_q10(input [15:0] ms, input [31:0] cyc_ms_q10);
	begin
		ms_to_cycles_q10 = ({32'd0, ms} * {16'd0, cyc_ms_q10}) >> 10;
	end
endfunction

// ---------------------------------------------------------------------------
// Decode current byte into a completed pulse, when possible.
// For v1/v2 overflow, add_offset is the 00 marker offset, not byte 3 of the
// duration field, so the top-level never resumes inside an overflow token.
// ---------------------------------------------------------------------------
reg        add_valid;
reg [47:0] add_cycles;
reg [24:0] add_offset;
reg [23:0] ovf_duration_next;

always @(*) begin
	add_valid = 1'b0;
	add_cycles = 48'd0;
	add_offset = tap_addr;
	ovf_duration_next = ovf_duration;

	if (tap_wr && state == ST_DATA) begin
		if (ovf_bytes_left != 0) begin
			case (ovf_bytes_left)
				2'd3: ovf_duration_next = {ovf_duration[23:8],  tap_data};
				2'd2: ovf_duration_next = {ovf_duration[23:16], tap_data, ovf_duration[7:0]};
				2'd1: ovf_duration_next = {tap_data, ovf_duration[15:0]};
				default: ovf_duration_next = ovf_duration;
			endcase

			if (ovf_bytes_left == 2'd1) begin
				add_valid = 1'b1;
				add_cycles = {24'd0, ovf_duration_next};
				add_offset = ovf_start_offset;
			end
		end else if (tap_data == 8'd0) begin
			if (tap_version == 2'd0) begin
				// v0: 00 is a fixed 20000-cycle pulse.
				add_valid = 1'b1;
				add_cycles = 48'd20000;
				add_offset = tap_addr;
			end
			// v1/v2: 00 starts an overflow token; pulse completes after 3 bytes.
		end else begin
			add_valid = 1'b1;
			add_cycles = {40'd0, tap_data} * 48'd8;
			add_offset = tap_addr;
		end
	end
end


// Request HPS download throttling whenever this pulse may cross one or more
// counter boundaries. This prevents losing TAP bytes while the FSM emits map
// entries for long pulses/silences.
wire [47:0] time_acc_after_add = time_acc_cycles + add_cycles;
assign wait_req = busy && ((state == ST_WRITE_MAP && time_acc_cycles >= target_cycles) ||
                           (state == ST_DATA && add_valid && time_acc_after_add >= target_cycles));

wire [47:0] dist_to_pulse_start = target_cycles - pulse_start_cycles;
wire [47:0] dist_to_pulse_end   = time_acc_cycles - target_cycles;
wire [24:0] nearest_safe_offset = (dist_to_pulse_start <= dist_to_pulse_end) ? pulse_start_offset : pulse_end_offset;

// ---------------------------------------------------------------------------
// FSM
// ---------------------------------------------------------------------------
always @(posedge clk) begin
	if (!reset_n) begin
		state <= ST_IDLE;
		busy <= 1'b0;
		ready <= 1'b0;
		map_wr <= 1'b0;
		map_addr <= {MAP_AW{1'b0}};
		map_data <= 25'd0;
		map_max <= {MAP_AW{1'b0}};
		count <= {MAP_AW{1'b0}};
		time_acc_cycles <= 48'd0;
		target_cycles <= 48'd0;
		threshold_ms <= THRESH_BASE[15:0];
		cycles_per_ms_q10 <= TAP_PLAYER_Q10;
		pulse_start_cycles <= 48'd0;
		pulse_start_offset <= 25'd20;
		pulse_end_offset <= 25'd20;
		ovf_bytes_left <= 2'd0;
		ovf_duration <= 24'd0;
		ovf_start_offset <= 25'd0;
		done_pending <= 1'b0;
		tap_version <= 2'd0;
	end else begin
		map_wr <= 1'b0;

		if (tap_done) done_pending <= 1'b1;
		else if (!busy) done_pending <= 1'b0;

		case (state)
			ST_IDLE: begin
				if (start) begin
					state <= ST_HEADER;
					busy <= 1'b1;
					ready <= 1'b0;
					count <= {MAP_AW{1'b0}};
					map_max <= {MAP_AW{1'b0}};
					time_acc_cycles <= 48'd0;
					threshold_ms <= THRESH_BASE[15:0];
					ovf_bytes_left <= 2'd0;
					ovf_duration <= 24'd0;
					ovf_start_offset <= 25'd0;
					done_pending <= 1'b0;
					cycles_per_ms_q10 <= TAP_PLAYER_Q10;
					pulse_start_cycles <= 48'd0;
					pulse_start_offset <= 25'd20;
					pulse_end_offset <= 25'd20;
				end
			end

			ST_HEADER: begin
				if (tap_wr && tap_addr < 25'd20) begin
					if (tap_addr == 25'd12) tap_version <= tap_data[1:0];

					if (tap_addr == 25'd19) begin
						cycles_per_ms_q10 <= TAP_PLAYER_Q10;
						target_cycles <= ms_to_cycles_q10(THRESH_BASE[15:0], TAP_PLAYER_Q10);

						// map[0] must be the beginning of the TAP stream so REW-to-start is safe.
						map_wr <= 1'b1;
						map_addr <= {MAP_AW{1'b0}};
						map_data <= 25'd0;
						count <= {{(MAP_AW-1){1'b0}}, 1'b1};
						state <= ST_DATA;
					end
				end
			end

			ST_DATA: begin
				if (tap_wr) begin
					if (ovf_bytes_left != 0) begin
						ovf_duration <= ovf_duration_next;
						ovf_bytes_left <= ovf_bytes_left - 1'd1;
					end else if (tap_data == 8'd0 && tap_version != 2'd0) begin
						ovf_bytes_left <= 2'd3;
						ovf_duration <= 24'd0;
						ovf_start_offset <= tap_addr;
					end
				end

				if (add_valid) begin
					pulse_start_cycles <= time_acc_cycles;
					pulse_start_offset <= add_offset;
					pulse_end_offset <= tap_addr + 1'd1;
					time_acc_cycles <= time_acc_cycles + add_cycles;
					state <= ST_WRITE_MAP;
				end else if (done_pending) begin
					state <= ST_WRITE_MAP;
				end
			end

			ST_WRITE_MAP: begin
				if ((count < ABS_MAX[MAP_AW-1:0]) && (count < {MAP_AW{1'b1}}) && (time_acc_cycles >= target_cycles)) begin
					map_wr <= 1'b1;
					map_addr <= count;
					map_data <= nearest_safe_offset;
					count <= count + 1'd1;
					threshold_ms <= threshold_ms + THRESH_INC[15:0];
					target_cycles <= target_cycles + ms_to_cycles_q10(threshold_ms + THRESH_INC[15:0], cycles_per_ms_q10);
				end else begin
					map_max <= count;
					if (done_pending) begin
						state <= ST_DONE;
						ready <= 1'b1;
						busy <= 1'b0;
					end else begin
						state <= ST_DATA;
					end
				end
			end

			ST_DONE: begin
				if (start) begin
					state <= ST_HEADER;
					busy <= 1'b1;
					ready <= 1'b0;
					count <= {MAP_AW{1'b0}};
					map_max <= {MAP_AW{1'b0}};
					time_acc_cycles <= 48'd0;
					threshold_ms <= THRESH_BASE[15:0];
					ovf_bytes_left <= 2'd0;
					ovf_duration <= 24'd0;
					ovf_start_offset <= 25'd0;
					done_pending <= 1'b0;
					cycles_per_ms_q10 <= TAP_PLAYER_Q10;
					pulse_start_cycles <= 48'd0;
					pulse_start_offset <= 25'd20;
					pulse_end_offset <= 25'd20;
				end
			end

			default: state <= ST_IDLE;
		endcase
	end
end

endmodule
