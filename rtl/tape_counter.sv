`timescale 1ns/1ps
// ============================================================================
// C1530 Datassette - Tape Counter with on-screen overlay
//
// Improved version of the mechanical tape counter.
//
// Key fixes/changes vs. the original:
//  1. FIXED: rewind digit decrement (the original accidentally incremented d_tens
//     when rolling under 0, breaking the counter during REW).
//  2. Added active-low reset_n input for clean FPGA initialization.
//  3. Replaced the huge nested digit case with a compact FONT ROM array.
//  4. Encapsulated BCD increment/decrement in helper functions.
//  5. Derived clock-divider values from parameters instead of hard-coded literals.
//  6. Used always_ff / always_comb consistently and cleaned up magic numbers.
//  7. Made overlay position configurable via parameters.
//  8. FIX: Widened tick_div / wind_div to prevent counter freeze on clocks >= 65MHz.
//  9. FIX: Uncoupled vblank coordinate resets from ce to guarantee clean sweeps.
// ============================================================================

module tape_counter #(
	parameter int CLK_HZ       = 32_000_000,
	parameter int TICK_HZ      = 1000,        // 1 kHz -> 1 tick = 1 ms of tape
	parameter int THRESH_BASE  = 2693,        // ms/rotation at tape start
	parameter int THRESH_INC   = 6,           // ms/rotation added per rotation
	parameter int ABS_MAX      = 8191,        // absolute rotation saturation / 13-bit time-map limit
	parameter int WIND_MS      = 476,         // ms per counter click during FF/REW
	parameter int POS_X_PAL    = 316,         // align with drive overlay X origin (PAL)
	parameter int POS_X_NTSC   = 323,         // align with drive overlay X origin (NTSC)
	parameter int POS_Y_PAL    = 249,         // third drive-overlay row (PAL: 237 + 12)
	parameter int POS_Y_NTSC   = 241          // third drive-overlay row (NTSC: 229 + 12)
) (
	input        clk,         // clk_sys (~32 MHz)
	input        ce,          // ~8 MHz pixel clock-enable
	input        reset_n,     // active-low reset
	input        hblank,
	input        vblank,
	input        ntsc,

	// Control
	input        enable,        // 1 = overlay visible
	input        tape_loaded,   // 1 = a tape is loaded
	input        new_tape,      // pulse/level: reset counter & position
	input        counter_reset, // OSD "Tape Counter Reset" pulse
	input [24:0] tap_play_addr, // current TAP file position
	input [24:0] tap_last_addr, // total TAP file size

	// Transport state from c1530 (active low)
	input        cass_run,      // 0 = motor rotating
	input        cass_sense,    // 0 = PLAY pressed

	// Winding (top-level guarantees mutual exclusion)
	input        ff,            // 1 = fast-forward active
	input        rew,           // 1 = rewind active

	// Synchronization back to the top-level tape position
	output       wind_step,
	output [12:0] abs_count,       // absolute counter value (index into time_map)
	output       at_tape_start,

	// Video mixer: 0=Transparent, 1=Green, 2=Yellow, 3=Red, 4=Blue
	output [2:0] pixel_color
);

// ---------------------------------------------------------------------------
// Local constants
// ---------------------------------------------------------------------------
localparam TICK_DIV   = CLK_HZ / TICK_HZ;   // 32000 at 32 MHz / 1 kHz
localparam WIND_TICKS = (WIND_MS < 1) ? 1 : WIND_MS;

localparam [2:0] C_TRANSPARENT = 3'd0;
localparam [2:0] C_GREEN       = 3'd1;
localparam [2:0] C_YELLOW      = 3'd2;
localparam [2:0] C_RED         = 3'd3;
localparam [2:0] C_BLUE        = 3'd4;

// ---------------------------------------------------------------------------
// Font ROM Lookup function (Avoids iverilog multi-dimensional array limitations)
// ---------------------------------------------------------------------------
function automatic [4:0] get_font_row(input [4:0] char, input [2:0] row);
	reg [4:0] val;
	begin
		val = 5'b00000;
		case (char)
			5'd0: begin
				case(row)
					0: val = 5'b01110; 1: val = 5'b10001; 2: val = 5'b10001; 3: val = 5'b10001; 4: val = 5'b01110;
				endcase
			end
			5'd1: begin
				case(row)
					0: val = 5'b00100; 1: val = 5'b01100; 2: val = 5'b00100; 3: val = 5'b00100; 4: val = 5'b01110;
				endcase
			end
			5'd2: begin
				case(row)
					0: val = 5'b01110; 1: val = 5'b10001; 2: val = 5'b00110; 3: val = 5'b01000; 4: val = 5'b11111;
				endcase
			end
			5'd3: begin
				case(row)
					0: val = 5'b11110; 1: val = 5'b00001; 2: val = 5'b01110; 3: val = 5'b00001; 4: val = 5'b11110;
				endcase
			end
			5'd4: begin
				case(row)
					0: val = 5'b10001; 1: val = 5'b10001; 2: val = 5'b11111; 3: val = 5'b00001; 4: val = 5'b00001;
				endcase
			end
			5'd5: begin
				case(row)
					0: val = 5'b11111; 1: val = 5'b10000; 2: val = 5'b11110; 3: val = 5'b00001; 4: val = 5'b11110;
				endcase
			end
			5'd6: begin
				case(row)
					0: val = 5'b01110; 1: val = 5'b10000; 2: val = 5'b11110; 3: val = 5'b10001; 4: val = 5'b01110;
				endcase
			end
			5'd7: begin
				case(row)
					0: val = 5'b11111; 1: val = 5'b00001; 2: val = 5'b00010; 3: val = 5'b00100; 4: val = 5'b00100;
				endcase
			end
			5'd8: begin
				case(row)
					0: val = 5'b01110; 1: val = 5'b10001; 2: val = 5'b01110; 3: val = 5'b10001; 4: val = 5'b01110;
				endcase
			end
			5'd9: begin
				case(row)
					0: val = 5'b01110; 1: val = 5'b10001; 2: val = 5'b01111; 3: val = 5'b00001; 4: val = 5'b01110;
				endcase
			end
			// STOP: filled square
			5'd26: begin
				case(row)
					0: val = 5'b11111; 1: val = 5'b11111; 2: val = 5'b11111; 3: val = 5'b11111; 4: val = 5'b11111;
				endcase
			end
			// PAUSE: two vertical bars
			5'd27: begin
				case(row)
					0: val = 5'b11011; 1: val = 5'b11011; 2: val = 5'b11011; 3: val = 5'b11011; 4: val = 5'b11011;
				endcase
			end
			// PLAY: right-pointing triangle
			5'd28: begin
				case(row)
					0: val = 5'b10000; 1: val = 5'b11000; 2: val = 5'b11100; 3: val = 5'b11000; 4: val = 5'b10000;
				endcase
			end
			// REW: double left triangles
			5'd29: begin
				case(row)
					0: val = 5'b00101; 1: val = 5'b01101; 2: val = 5'b11111; 3: val = 5'b01101; 4: val = 5'b00101;
				endcase
			end
			// FFWD: double right triangles
			5'd30: begin
				case(row)
					0: val = 5'b10100; 1: val = 5'b10110; 2: val = 5'b11111; 3: val = 5'b10110; 4: val = 5'b10100;
				endcase
			end
			// LOAD/cassette icon
			5'd31: begin
				case(row)
					0: val = 5'b11111; 1: val = 5'b10001; 2: val = 5'b11111; 3: val = 5'b01010; 4: val = 5'b11111;
				endcase
			end
			default: val = 5'b00000;
		endcase
		get_font_row = val;
	end
endfunction


// ---------------------------------------------------------------------------
// BCD helpers
// ---------------------------------------------------------------------------
function automatic [11:0] bcd_inc(input [11:0] bcd);
	reg [3:0] h, t, o;
	begin
		h = bcd[11:8]; t = bcd[7:4]; o = bcd[3:0];
		if (o == 4'd9) begin
			o = 4'd0;
			if (t == 4'd9) begin
				t = 4'd0;
				if (h == 4'd9) h = 4'd0;
				else           h = h + 4'd1;
			end else begin
				t = t + 4'd1;
			end
		end else begin
			o = o + 4'd1;
		end
		bcd_inc = {h, t, o};
	end
endfunction

function automatic [11:0] bcd_dec(input [11:0] bcd);
	reg [3:0] h, t, o;
	begin
		h = bcd[11:8]; t = bcd[7:4]; o = bcd[3:0];
		if (o == 4'd0) begin
			o = 4'd9;
			if (t == 4'd0) begin
				t = 4'd9;
				if (h == 4'd0) h = 4'd9;
				else           h = h - 4'd1;
			end else begin
				t = t - 4'd1;   // FIX: original had +1 here, causing REW to go wrong
			end
		end else begin
			o = o - 4'd1;
		end
		bcd_dec = {h, t, o};
	end
endfunction

// ---------------------------------------------------------------------------
// Tick generators
// ---------------------------------------------------------------------------
// FIX: Widened tick_div dynamically to prevent wrap-around bugs at high frequencies
reg [$clog2(TICK_DIV):0] tick_div = 0;
reg                      tick_1k  = 0;
always @(posedge clk) begin
	if (!reset_n) begin
		tick_div <= 0;
		tick_1k  <= 0;
	end else begin
		tick_1k <= 0;
		if (tick_div >= TICK_DIV[$clog2(TICK_DIV):0] - 1'd1) begin
			tick_div <= 0;
			tick_1k  <= 1;
		end else begin
			tick_div <= tick_div + 1'd1;
		end
	end
end

// FIX: Widened wind_div to dynamically fit WIND_TICKS values
reg [$clog2(WIND_TICKS):0] wind_div  = 0;
reg                        wind_tick = 0;
always @(posedge clk) begin
	if (!reset_n) begin
		wind_div  <= 0;
		wind_tick <= 0;
	end else begin
		wind_tick <= 0;
		if (!winding) begin
			wind_div <= 0;
		end else if (tick_1k) begin
			if (wind_div >= WIND_TICKS[$clog2(WIND_TICKS):0] - 1'd1) begin
				wind_div  <= 0;
				wind_tick <= 1;
			end else begin
				wind_div <= wind_div + 1'd1;
			end
		end
	end
end

// ---------------------------------------------------------------------------
// Transport state (combinational)
// ---------------------------------------------------------------------------
wire at_end  = tape_loaded & (tap_play_addr >= tap_last_addr);
wire winding = tape_loaded & (ff | rew); // allow REW even after end-of-tape
wire playing = tape_loaded & ~at_end & ~cass_run & ~cass_sense & ~winding;
wire paused  = tape_loaded & ~at_end & cass_run & ~cass_sense & ~winding;
// ---------------------------------------------------------------------------
// Physical counter model: accumulating time vs. growing reel radius
// ---------------------------------------------------------------------------
reg [15:0] pos_acc   = 0;
reg [12:0] abs_count_r = 0;
reg [15:0] threshold = THRESH_BASE[15:0];
reg [3:0]  d_ones    = 0;
reg [3:0]  d_tens    = 0;
reg [3:0]  d_huns    = 0;

reg counter_reset_d = 0;
wire counter_reset_edge = counter_reset & ~counter_reset_d;

always @(posedge clk) begin
	if (!reset_n) begin
		pos_acc         <= 0;
		abs_count_r     <= 0;
		threshold       <= THRESH_BASE[15:0];
		d_ones          <= 0;
		d_tens          <= 0;
		d_huns          <= 0;
		counter_reset_d <= 0;
	end else begin
		counter_reset_d <= counter_reset;

		if (new_tape || !tape_loaded) begin
			pos_acc     <= 0;
			abs_count_r <= 0;
			threshold   <= THRESH_BASE[15:0];
			d_ones      <= 0;
			d_tens      <= 0;
			d_huns      <= 0;
		end else begin
			if (counter_reset_edge) begin
				// Mechanical reset only clears the digits; absolute position is kept.
				d_ones <= 0;
				d_tens <= 0;
				d_huns <= 0;
			end

			if (tick_1k && playing && !winding) begin
				if (pos_acc + 1'd1 >= threshold) begin
					pos_acc <= (pos_acc + 1'd1) - threshold;
					if (abs_count_r < ABS_MAX[12:0]) begin
						abs_count_r <= abs_count_r + 1'd1;
						threshold <= threshold + THRESH_INC[15:0];
					end
					if (!counter_reset_edge) begin
						{d_huns, d_tens, d_ones} <= bcd_inc({d_huns, d_tens, d_ones});
					end
				end else begin
					pos_acc <= pos_acc + 1'd1;
				end
			end

			if (wind_tick && !counter_reset_edge) begin
				pos_acc <= 0;
				if (ff && abs_count_r < ABS_MAX[12:0]) begin
					abs_count_r <= abs_count_r + 1'd1;
					threshold <= threshold + THRESH_INC[15:0];
					{d_huns, d_tens, d_ones} <= bcd_inc({d_huns, d_tens, d_ones});
				end else if (rew && abs_count_r != 0) begin
					abs_count_r <= abs_count_r - 1'd1;
					threshold <= (threshold >= THRESH_BASE[15:0] + THRESH_INC[15:0])
					             ? threshold - THRESH_INC[15:0]
					             : THRESH_BASE[15:0];
					{d_huns, d_tens, d_ones} <= bcd_dec({d_huns, d_tens, d_ones});
				end
			end
		end
	end
end

// ===========================================================================
// Rendering overlay
// ===========================================================================
localparam bit [9:0] TC_W = 10'd30; // 5 cells * 6 px
localparam bit [9:0] TC_H = 10'd6;  // 5 font + 1 spacing

wire [9:0] base_x = ntsc ? POS_X_NTSC[9:0] : POS_X_PAL[9:0];
wire [9:0] base_y = ntsc ? POS_Y_NTSC[9:0] : POS_Y_PAL[9:0];

reg [9:0] x_pos = 0;
reg [9:0] y_pos = 0;
reg       old_hblank = 0;

always @(posedge clk) begin
	if (!reset_n) begin
		x_pos      <= 0;
		y_pos      <= 0;
		old_hblank <= 0;
	end else begin
		if (hblank) x_pos <= 0;
		else if (ce) x_pos <= x_pos + 1'd1;

		if (ce) old_hblank <= hblank;

		if (vblank) y_pos <= 0;
		else if (ce) begin
			if (old_hblank && !hblank) y_pos <= y_pos + 1'd1;
		end
	end
end

wire tc_visible = enable && tape_loaded;
wire tc_area = tc_visible &&
               (x_pos >= base_x) && (x_pos < base_x + TC_W) &&
               (y_pos >= base_y) && (y_pos < base_y + TC_H);

reg [2:0] tc_col_r = 0;
reg [2:0] tc_px_r  = 0;
reg [2:0] tc_py_r  = 0;

always @(posedge clk) begin
	if (!reset_n) begin
		tc_col_r <= 0;
		tc_px_r  <= 0;
	end else if (ce) begin
		// tc_col_r / tc_px_r: aggiornati ogni pixel nella zona overlay
		if (hblank) begin
			tc_col_r <= 0;
			tc_px_r  <= 0;
		end else if (x_pos == base_x - 10'd1) begin
			tc_col_r <= 0;
			tc_px_r  <= 0;
		end else if (tc_area) begin
			if (tc_px_r == 3'd5) begin
				tc_px_r  <= 0;
				tc_col_r <= tc_col_r + 1'd1;
			end else begin
				tc_px_r  <= tc_px_r + 1'd1;
			end
		end
	end
end

// FIX: Uncouple vblank coordinate resets from ce to guarantee clean sweeps under all conditions
always @(posedge clk) begin
	if (!reset_n) begin
		tc_py_r <= 0;
	end else begin
		if (vblank) begin
			tc_py_r <= 0;
		end else if (ce) begin
			if (old_hblank && !hblank) begin
				if (y_pos == base_y - 10'd1) begin
					tc_py_r <= 0;
				end else if (y_pos >= base_y && y_pos < base_y + TC_H) begin
					if (tc_py_r == 3'd5) tc_py_r <= 0;
					else                 tc_py_r <= tc_py_r + 1'd1;
				end else begin
					tc_py_r <= 0;
				end
			end
		end
	end
end

// Character selection: transport-state glyph in col 0, then hundreds/tens/ones.
reg [4:0] tc_state_char;
always @(*) begin
	if (ff)             tc_state_char = 5'd30; // FFWD
	else if (rew)       tc_state_char = 5'd29; // REW
	else if (playing)   tc_state_char = 5'd28; // PLAY
	else if (paused)    tc_state_char = 5'd27; // PAUSE
	else                tc_state_char = 5'd26; // STOP
end

reg [4:0] tc_char;
always @(*) begin
	case (tc_col_r)
		3'd0: tc_char = tc_state_char;
		3'd1: tc_char = 5'h11;              // blank space
		3'd2: tc_char = {1'b0, d_huns};     // hundreds
		3'd3: tc_char = {1'b0, d_tens};     // tens
		3'd4: tc_char = {1'b0, d_ones};     // ones
		default: tc_char = 5'h11;           // blank
	endcase
end

wire valid_tc_pixel = tc_area && (tc_px_r < 5) && (tc_py_r < 5);

// ---------------------------------------------------------------------------
// Pipeline stage 1: latch cell coordinates and state
// ---------------------------------------------------------------------------
reg [4:0] char_s1;
reg [2:0] px_s1, py_s1;
reg       valid_s1;
reg [2:0] color_s1;

always @(posedge clk) begin
	if (!reset_n) begin
		char_s1    <= 0;
		px_s1      <= 0;
		py_s1      <= 0;
		valid_s1   <= 0;
		color_s1   <= C_TRANSPARENT;
	end else if (ce) begin
		char_s1    <= tc_char;
		px_s1      <= tc_px_r;
		py_s1      <= tc_py_r;
		valid_s1   <= valid_tc_pixel;
		color_s1   <= (ff || rew) ? C_BLUE :
		              playing    ? C_GREEN :
		              paused     ? C_YELLOW : C_RED;
	end
end

// ---------------------------------------------------------------------------
// Pipeline stage 2: font lookup
// ---------------------------------------------------------------------------
reg [4:0] font_row_s2;
reg [2:0] px_s2;
reg       valid_s2;
reg [2:0] color_s2;

always @(posedge clk) begin
	if (!reset_n) begin
		font_row_s2 <= 0;
		px_s2       <= 0;
		valid_s2    <= 0;
		color_s2    <= C_TRANSPARENT;
	end else if (ce) begin
		font_row_s2 <= get_font_row(char_s1, py_s1);
		px_s2       <= px_s1;
		valid_s2    <= valid_s1;
		color_s2    <= color_s1;
	end
end

// ---------------------------------------------------------------------------
// Pipeline stage 3: pixel shift and color
// ---------------------------------------------------------------------------
wire [2:0] px_rev   = (px_s2 < 5) ? 3'd4 - px_s2 : 3'd0;
wire       pixel_on = (px_s2 < 5) ? font_row_s2[px_rev] : 1'b0;

reg [2:0] pixel_color_out;
always @(posedge clk) begin
	if (!reset_n) begin
		pixel_color_out <= C_TRANSPARENT;
	end else if (ce) begin
		if (valid_s2 && pixel_on)
			pixel_color_out <= color_s2;
		else
			pixel_color_out <= C_TRANSPARENT;
	end
end

assign pixel_color = pixel_color_out;

// ---------------------------------------------------------------------------
// Position synchronization outputs
// ---------------------------------------------------------------------------
assign wind_step     = wind_tick;
assign abs_count     = abs_count_r;
assign at_tape_start = (abs_count_r == 0);

endmodule
