//
// c1541_track
// Copyright (c) 2016 Sorgelig
//
// This source file is free software: you can redistribute it and/or modify
// it under the terms of the Lesser GNU General Public License as published
// by the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This source file is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
//
// =============================================================================
// DDRAM Background/Foreground FSM DMA Engine by Robin Wünderlich:
//
// This module manages the high-speed transfer of floppy disk track data between
// the DDRAM G64 image, the active drive emulation buffer, and the SD card.
//
// Image loading:
//   - c64.cpp (ARM) loads complete G64 (or converted D64) images into DDRAM.
//   - FGPA: Base addresses: 0x06000000 (Drive 8) and 0x06040000 (Drive 9).
//	 - FGPA: 64bit index address   ARM: bytes address (=FPGA address *8)
//
// Foreground Tasks:
//   - Track Change (Read): When the 1541 changes tracks, the FSM immediately
//     bursts the requested track data from DDRAM directly into the BRAM track
//     buffer inside the `direct_gcr` module (now 64 bit wide).
//   - Track Save (Write): When the 1541 modifies a track, it triggers
//     `save_track`. The FSM reads the modified track from the BRAM buffer and
//     writes it back to the main image in DDRAM, marking the track as "dirty".
//
// Background Tasks (Flushing):
//   - When the FSM is idle, it scans the `dirty_tracks` bitmask.
//   - If a dirty track is found, the FSM burst copies the data from DDRAM into a
//     dedicated local background BRAM buffer (`bg_buffer`).
//   - It then signals the ARM/HPS (`sd_wr`, `sd_lba`) to stream that background
//     buffer back to the physical .G64 file on the SD card. This ensures saves
//     are non-blocking and do not stall the real-time C64 drive emulation.
//	 - From a user perspective this is seamless and intuitive, he does not have
//     to open the MiSTer menu in order to save.
//
// =============================================================================
// Track Change/Loading Speed Comparison
// =============================================================================
// | Method                                             | Time       |
// |----------------------------------------------------|------------|
// | SD HPS_IO (miniz streaming from ZIP)               | ~ 8.90 ms  |
// | SD HPS_IO (normal file)                            | ~ 4.30 ms  |
// | SD HPS_IO (normal file, WIDE 16bit I/O)            | ~ 2.35 ms  |
// | DDRAM DMA (Burst count = 1)                        | ~ 0.60 ms  |
// | DDRAM DMA (Burst count = 32) (Current Method)      | ~ 0.03 ms  |
// =============================================================================
// Some timing sensitive disk protections fail at half-track changes > ~2.2ms
///////////////////////////////////////////////////////////////////////////////

module c1541_track #(parameter BURST_LEN = 32)
(
	input         clk,
	input         reset,

	input         gcr_mode,

	output [31:0] sd_lba,
	output  [5:0] sd_blk_cnt,
	output reg    sd_rd,
	output reg    sd_wr,
	input         sd_ack,

	input         save_track,
	input         change,
	input   [6:0] track,

	output wire   busy_flushing,

	input         drive_num,

	// DDRAM Interface
	input         DDRAM_BUSY,
	output  [7:0] DDRAM_BURSTCNT,
	output [28:0] DDRAM_ADDR,
	input  [63:0] DDRAM_DOUT,
	input         DDRAM_DOUT_READY,
	output        DDRAM_RD,
	output        DDRAM_WE,
	output [63:0] DDRAM_DIN,
	output  [7:0] DDRAM_BE,

	// DMA Track Buffer Interface
	output [13:0] dma_buff_addr,
	output [63:0] dma_buff_dout,
	output		  dma_buff_wr,
	input  [63:0] dma_buff_din,

	// Background Save Interface
	input  [13:0] sd_buff_addr,
	output [63:0] bg_buff_dout
);

// -----------------------------------------------------------------------------
// FSM State Definitions
// -----------------------------------------------------------------------------

// Dispatcher
localparam IDLE                   = 4'd0;

// DMA from DDRAM to track buffer (foreground)
//                to bg buffer    (background)
localparam REQ_OFFSET_RD          = 4'd1;
localparam READ_OFFSET            = 4'd2;
localparam START_DMA              = 4'd3;
localparam REQ_BURST_RD           = 4'd4;
localparam BURST_DDRAM_TO_BUFF    = 4'd5;
localparam CHECK_DONE             = 4'd6;
localparam GEN_DUMMY              = 4'd7;

// DMA from track buffer to DDRAM
localparam PREP_DDRAM_WRITE       = 4'd9;
localparam WAIT_STATE_1_BUFF      = 4'd11;
localparam WAIT_STATE_2_BUFF      = 4'd8;
localparam READ_BUFF              = 4'd12;
localparam WRITE_TO_DDRAM         = 4'd14;
localparam FINISH_BEAT            = 4'd15;

// -----------------------------------------------------------------------------
// External Signal Synchronization
// -----------------------------------------------------------------------------

wire [6:0] track_s;
wire       change_s, save_track_s, reset_s;

iecdrv_sync #(7) track_sync  (clk, track,      track_s);
iecdrv_sync #(1) change_sync (clk, change,     change_s);
iecdrv_sync #(1) save_sync   (clk, save_track, save_track_s);
iecdrv_sync #(1) reset_sync  (clk, reset,      reset_s);

// -----------------------------------------------------------------------------
// DDRAM Interface Logic
// -----------------------------------------------------------------------------

wire [28:0] ddr_base_addr_q = 29'h06000000 + (drive_num ? 29'h00040000 : 29'h0);
reg  [28:0] ddr_offset_q;

assign DDRAM_ADDR     = ddr_base_addr_q + ddr_offset_q;
assign DDRAM_BURSTCNT = (dma_state == REQ_BURST_RD) ? dma_burst_len : 8'd1;
assign DDRAM_RD       = (dma_state == REQ_OFFSET_RD) || (dma_state == REQ_BURST_RD);
assign DDRAM_WE       = (dma_state == WRITE_TO_DDRAM);
assign DDRAM_DIN      = dma_data_latch;
assign DDRAM_BE       = (dma_state == WRITE_TO_DDRAM) ? be_mask : 8'hFF;

// Combinatorial byte enable mask generation
reg [7:0] be_mask;
always @(*) begin
	reg [3:0] end_byte;
	reg [3:0] start_byte;

	start_byte = (dma_ptr == 0 ) ? {1'b0, dma_align} : 4'd0;
	end_byte   = (dma_last_sum) ? dma_last_sum : 4'd8;
	be_mask    = 8'(((9'h01 << end_byte) - 9'h01) & ~((9'h01 << start_byte) - 9'h01));
end

// -----------------------------------------------------------------------------
// ARM/SD Interface (Used for triggering SD-card write-back)
// -----------------------------------------------------------------------------

reg [31:0] lba;
assign     sd_lba     = lba;
assign     sd_blk_cnt = 6'd31; // (31+1) * 256 = 8192 bytes

// -----------------------------------------------------------------------------
// Internal DMA & Buffer Interface Logic
// -----------------------------------------------------------------------------

reg [63:0]  dma_data_latch;
reg [63:0]  dma_prev_dout;
reg [15:0]  dma_total_len;
reg [13:0]  dma_ptr;
reg [7:0]   dma_burst_count;
reg [2:0]   dma_align;
reg [3:0]   dma_state;
reg [2:0]   dma_last_sum;
reg         dma_first_q;


reg [84:0]  dirty_tracks;
reg [31:0]  bg_track_offset;
reg [6:0]   bg_track;
reg [6:0]   scan_track;
reg         sd_state;
reg         bg_state;


assign dma_buff_dout = (dma_state == GEN_DUMMY) ? 64'd0 :
                       (dma_align == 0) ? DDRAM_DOUT :
                       ((DDRAM_DOUT << ((8 - dma_align) * 8)) | (dma_prev_dout >> (dma_align * 8)));
wire   dma_bram_wr   = (dma_state == GEN_DUMMY) ? 1'b1 :
                       (dma_state == BURST_DDRAM_TO_BUFF && DDRAM_DOUT_READY) ?
                       ((dma_align == 0) ? 1'b1 : !dma_first_q) : 1'b0;

wire [7:0]  dma_burst_len  = (bytes_left < 14'(BURST_LEN * 8)) ?
                             8'(bytes_left >> 3) : 8'(BURST_LEN);
wire [13:0] bytes_left     = 14'h2000 - dma_ptr;

assign dma_buff_addr = dma_ptr;
assign dma_buff_wr   = bg_state ? 1'b0 : dma_bram_wr;
wire   bg_buff_wr    = bg_state ? dma_bram_wr : 1'b0;

iecdrv_bitmem64SP #(10) bg_buffer
(
	.clock_a(clk),
	.address_a(bg_state ? dma_ptr[12:3] : sd_buff_addr[12:3]),
	.data_a(dma_buff_dout),
	.wren_a(bg_buff_wr),
	.q_a(bg_buff_dout)
);

// -----------------------------------------------------------------------------
// Busy State Aggregation
// -----------------------------------------------------------------------------

assign busy_flushing = (|dirty_tracks) || sd_state || ((dma_state != IDLE) && bg_state);

// -----------------------------------------------------------------------------
// DMA Control FSM
// -----------------------------------------------------------------------------

always @(posedge clk) begin
    reg [31:0] cur_track_offset; // G64 image track offset in bytes
	reg [6:0]  cur_track = 0;
	reg [6:0]  track_new;
	reg update     = 0;
	reg old_change = 0;
	reg old_save_track = 0;
	reg old_ack = 0;

	track_new <= track_s;

	old_change <= change_s;
	if(~old_change & change_s) begin
		update <= 1;
		dirty_tracks <= 0;
	end

	old_ack <= sd_ack;
	if(sd_ack) {sd_rd,sd_wr} <= 0;

	if (reset_s) begin
		dma_state <= IDLE;
		sd_state  <= 0;
		bg_state  <= 0;
		cur_track <= '1; // out-of-band value, not yet initialized
		update    <= 1;
		dma_ptr   <= 0;
		sd_rd     <= 0;
		sd_wr     <= 0;
		old_save_track <= save_track_s;
		dirty_tracks   <= 0;
		scan_track     <= 0;
	end else begin
		if (sd_state) begin
			if(old_ack && ~sd_ack) begin
				sd_state <= 0;
			end
		end

		// =====================================================================
		// Main DMA Control FSM
		// =====================================================================
		case (dma_state)

			// --- Idle & Task Dispatcher ---
			// Priority 1: Foreground Track Save (save_track toggled)
			// Priority 2: Foreground Track Change (track_new updated or image mounted)
			// Priority 3: Background SD Flush (dirty_tracks queue not empty)
			IDLE: begin
				if (old_save_track != save_track_s) begin
					old_save_track <= save_track_s;
					if (~&cur_track[6:1]) begin
						// Don't save until cur_track initalized
						// and don't save if no G64 offset
						if (cur_track_offset != 0) begin
							bg_state <= 0;
							dma_state <= PREP_DDRAM_WRITE;
						end
					end
				end else if ((cur_track != track_new) || update) begin
					cur_track <= track_new;
					update    <= 0;
					dma_ptr   <= 0;
					bg_state  <= 0;
					// G64 header stores track offset table at $C
					// Translate byte offset to quadword index
					ddr_offset_q <= 29'((12 + track_new * 4) >> 3);
					dma_state    <= REQ_OFFSET_RD;
				end else if (dirty_tracks != 0 && sd_state == 0) begin
					// Round-robin scan for the next dirty track to flush
					if (dirty_tracks[scan_track]) begin
						dirty_tracks[scan_track] <= 0;
						bg_track     <= scan_track;
						bg_state     <= 1;
						dma_ptr      <= 0;
						ddr_offset_q <= 29'((12 + scan_track * 4) >> 3);
						dma_state    <= REQ_OFFSET_RD;
					end
					scan_track <= (scan_track >= 84) ? 7'd0 : scan_track + 1'd1;
				end
			end

			// =================================================================
			// DDRAM -> BRAM (FG Track Load / BG Fetch)
			// =================================================================

			// Fetch the 32-bit track offset pointer from the G64 header
			REQ_OFFSET_RD: begin
				if (!DDRAM_BUSY) dma_state <= READ_OFFSET;
			end

			READ_OFFSET: begin
				if (DDRAM_DOUT_READY) begin
					// The G64 header track offsets are 32-bit, but DDRAM_DOUT is 64-bit.
					// Offsets are 4-byte aligned, so we just  pick the upper or lower half.
					if (bg_state) begin
						bg_track_offset  <= ((12 + bg_track * 4) & 4) ?
										    DDRAM_DOUT[63:32] : DDRAM_DOUT[31:0];
					end else begin
						cur_track_offset <= ((12 + cur_track * 4) & 4) ?
											DDRAM_DOUT[63:32] : DDRAM_DOUT[31:0];
					end
					dma_state <= START_DMA;
				end
			end

			START_DMA: begin
				dma_ptr <= 0;
				if (bg_state) begin
					if (bg_track_offset == 0) begin
						dma_state <= GEN_DUMMY; // No track data, signal zero length to direct_gcr
					end else begin
						dma_align    <= bg_track_offset[2:0]; // Byte alignement (0-7)
						ddr_offset_q <= 29'(bg_track_offset >> 3); // 64-bit Quadword index
						dma_first_q  <= 1;
						dma_state    <= REQ_BURST_RD;
					end
				end else begin
					if (cur_track_offset == 0) begin
						dma_state <= GEN_DUMMY;
					end else begin
						dma_align    <= cur_track_offset[2:0];
						ddr_offset_q <= 29'(cur_track_offset >> 3);
						dma_first_q  <= 1;
						dma_state    <= REQ_BURST_RD;
					end
				end
			end

			REQ_BURST_RD: begin
				if (!DDRAM_BUSY) begin
					dma_state <= BURST_DDRAM_TO_BUFF;
					dma_burst_count <= dma_burst_len - 1'd1;
				end
			end

			// Because G64 track data rarely starts perfectly on a 64-bit boundary,
			// we buffer the previous 64-bit word and bit-shift across the boundary
			// using `dma_align` to construct a properly aligned word for the BRAM.
			BURST_DDRAM_TO_BUFF: begin
				if (DDRAM_DOUT_READY) begin
					dma_burst_count <= dma_burst_count - 1'd1;
					ddr_offset_q    <= ddr_offset_q + 1'd1;

					if (dma_align == 0) begin // Perfectly aligned
						dma_ptr <= dma_ptr + 4'd8;
					end else begin               // Misaligned (Requires shifting)
						dma_prev_dout <= DDRAM_DOUT; // Cache qword for shifting
						if (dma_first_q) begin
							dma_first_q <= 0;
						end else begin
							dma_ptr <= dma_ptr + 4'd8;
						end
					end

					// Request the next burst chunk when finished
					if (dma_burst_count == 0) begin
						dma_state <= CHECK_DONE;
					end
				end
			end

			// Check if DDRAM to buffer DMA transfer is complete.
			// If complete either return to idle (foreground transfer to track buffer),
			// or trigger an SD card flush (background transfer to bg buffer)
			CHECK_DONE: begin
				if (dma_ptr >= 14'h2000) begin
					if (bg_state) begin
						dma_state <= IDLE;
						bg_state <= 0;
						// Safety Check: If the user mounted a new disk during dma,
						// `update` will be 1, to not write to the new mount instead
						// of the old, discard the data and do NOT trigger sd_wr
						if (!update) begin
							lba      <= {25'd0, bg_track};
							sd_wr    <= 1;
							sd_state <= 1;
						end
						dirty_tracks[bg_track] <= 0;
					end else begin
						dma_state <= IDLE;
						dma_ptr   <= 0;
						bg_state     <= 0;
					end
				end else begin
					dma_state <= REQ_BURST_RD; // Keep bursting until 8KB is filled
				end
			end

			// Writes eight dummy bytes of zeroes to the start of the buffer,
			// signalling to direct_gcr, that no track data is available.
			// G64 tracks start with a two byte length indicator, followed by data.
			// The direct_gcr module creates virtual tracks on-the-fly for all
			// tracks with length < d6000
			GEN_DUMMY: begin
					dma_state <= IDLE;
					bg_state <= 0;
			end

			// =================================================================
			// BRAM -> DDRAM (Track Flush to Memory)
			// =================================================================

			PREP_DDRAM_WRITE: begin
				ddr_offset_q       <= 29'(cur_track_offset >> 3);
				dma_align          <= cur_track_offset[2:0];
				dma_last_sum       <= 0;
				dma_total_len      <= '1; // out-of-band value
				dma_ptr            <= 0;
				dma_data_latch     <= 0;
				dma_prev_dout      <= 0;
				dma_state          <= WAIT_STATE_1_BUFF;
			end

			// BRAM has a 2-cycle read latency
			WAIT_STATE_1_BUFF: begin
				dma_state <= WAIT_STATE_2_BUFF;
			end

			WAIT_STATE_2_BUFF: begin
				dma_state <= READ_BUFF;
			end

			READ_BUFF: begin
				// The first 2 bytes of track BRAM indicate track length in bytes.
				// The 2 byte header is directly followed by the gcr data payload.
				// So in total we transfer track length + 2 bytes.
				// We abort transfer of invalid sized tracks
				if (dma_ptr == 0 && dma_buff_din[15:0] <= 16'd8) begin
					dma_state <= IDLE; // Abort
				end else begin
					if (dma_ptr == 0) begin
						dma_total_len <= ((dma_buff_din[15:0] > 16'd8190) ?
										 16'd8192 : dma_buff_din[15:0] + 16'd2);
					end

					// Bit-shift the 64-bit BRAM word across the boundary so it cleanly
					// aligns with the target DDRAM memory offset.
					if (dma_align == 0) begin
						dma_data_latch <= dma_buff_din;
					end else begin
						dma_data_latch <= (dma_buff_din << (dma_align * 8)) |
										  (dma_prev_dout >> ((8 - dma_align) * 8));
					end
					dma_prev_dout <= dma_buff_din;

					// Set dma_last_sum on final write to adjust be_mask end_byte
					// dma_total_len initialized so that condition can't trigger
					// on first Q
					if ((dma_ptr + (16'd8 - {13'd0, dma_align})) >= dma_total_len) begin
						dma_last_sum <= 3'(dma_align + dma_total_len[2:0]);
					end
				dma_state <= WRITE_TO_DDRAM;
				end

			end

			WRITE_TO_DDRAM: begin
				if (!DDRAM_BUSY) begin
					// Advance DDR offset and BRAM pointer
					ddr_offset_q <= ddr_offset_q + 1'd1;
					dma_ptr      <= dma_ptr + 4'd8;
					// Check if we reached the end of the track using the CURRENT dma_ptr
					if (dma_ptr + (16'd8 - {13'd0, dma_align}) >= dma_total_len) begin
						dma_state <= IDLE;
						// Mark track as dirty so the background FSM will flush it to SD later
						if (!update) dirty_tracks[cur_track] <= 1'b1;
					end else begin
						// Loop back to fetch the next word from BRAM
						dma_state <= WAIT_STATE_1_BUFF;
					end
				end
			end

		endcase
	end
	end

endmodule
