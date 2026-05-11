// ============================================================================
// Drive OSD and Debug Overlay
//
// Functionality:
// - Displays drive track/activity status (Activity Only, Mounted, or Debug).
// - Generates a 2-bit color index to be blended into the final video output.
// - Debug mode: monitors DDRAM read/write history and specific address ranges.
//
// Clocking & Timing:
// - Pixel rendering and coordinate generation are gated by `ce` (~8MHz pixel clock)
//   to reduce power and relax routing/timing constraints.
// - only DDRAM snooping and video sync resets (hblank/vblank) run at full ~32MHz.
//
// Architecture:
// - Rendering uses a 3-stage pipeline to ensure low combinatorial load and
//   predictable timing closure. Video output lags coordinates by 3 `ce` cycles.
// ============================================================================
module drv_overlay (
	input clk,
	input ce,
	input hblank,
	input vblank,
	input ntsc,

	// Drive status
	input [1:0] drive_osd_mode, // 0=Activity Only, 1=If Mounted, 2=Debug, 3=Off
	input [1:0] drive_led,
	input [1:0] drive_mounted,
	input [6:0] drive_track_0,
	input [6:0] drive_track_1,
	input [1:0] drive_we,      // drive write enable or busy flushig tracks

	// debug data
	input valid,
	input [31:0] addr,
	input [63:0] data,
	input wr_valid,
	input [31:0] wr_addr,
	input [63:0] wr_data,
	input [31:0] base_addr,

	// pixel output for video mixer
	// 0=Transparent, 1=Green, 2=Yellow, 3=Red
	output [1:0] pixel_color
	);

// Debug info
// `hist_addr` and `hist_data` are rolling buffers for the last 8 DDRAM reads (addresses and value)
// `snoop_data` captures data specifically for 8-dword window starting at `base_addr`.
// The `wr_` prefixed variants do the same for write operations.
reg [31:0] hist_addr [0:7]     = '{default:0};
reg [63:0] hist_data [0:7]     = '{default:0};
reg [63:0] snoop_data [0:7]    = '{default:0};

reg [31:0] wr_hist_addr [0:7]  = '{default:0};
reg [63:0] wr_hist_data [0:7]  = '{default:0};
reg [63:0] wr_snoop_data [0:7] = '{default:0};

integer i;
always @(posedge clk) begin
	if (valid) begin
		for (i=7; i>0; i=i-1) begin
			hist_addr[i] <= hist_addr[i-1];
			hist_data[i] <= hist_data[i-1];
		end
		hist_addr[0] <= addr;
		hist_data[0] <= data;

		if (addr >= base_addr && addr < base_addr + 8) begin
			snoop_data[3'(addr - base_addr)] <= data;
		end
	end

	if (wr_valid) begin
		for (i=7; i>0; i=i-1) begin
			wr_hist_addr[i] <= wr_hist_addr[i-1];
			wr_hist_data[i] <= wr_hist_data[i-1];
		end
		wr_hist_addr[0] <= wr_addr;
		wr_hist_data[0] <= wr_data;

		if (wr_addr >= base_addr && wr_addr < base_addr + 8) begin
			wr_snoop_data[3'(wr_addr - base_addr)] <= wr_data;
		end
	end
end

// Coordinate Logic
reg [9:0] x_pos = 0;
reg [9:0] y_pos = 0;
reg old_hblank = 0;

always @(posedge clk) begin
	if (hblank) x_pos <= 0;
	else if (ce) x_pos <= x_pos + 1'd1;

	if (ce) old_hblank <= hblank;

	if (vblank) y_pos <= 0;
	else if (ce) begin
		if (old_hblank && ~hblank) y_pos <= y_pos + 1'd1;
	end
end

// Overlay Areas
wire debug_active = (drive_osd_mode == 2);
wire dbg_area     = (x_pos >= 32) && (x_pos < 32 + 51*6) &&
                    (y_pos >= 32) && (y_pos < 32 + 17*6);

wire [9:0] base_y  = ntsc ? 10'd229 : 10'd237;
wire [9:0] base_x  = ntsc ? 10'd323 : 10'd316;
wire       drv_area = (x_pos >= base_x) && (x_pos < base_x + 42) &&
                      (y_pos >= base_y) && (y_pos < base_y + 12);

// Coordinate generators
reg [5:0] dbg_col_r = 0;
reg [4:0] dbg_row_r = 0;
reg [2:0] dbg_px_r  = 0;
reg [2:0] dbg_py_r  = 0;

reg [2:0] drv_col_r = 0;
reg       drv_row_r = 0;
reg [2:0] drv_px_r  = 0;
reg [2:0] drv_py_r  = 0;

always @(posedge clk) begin
	if (hblank) begin
		dbg_col_r <= 0;
		dbg_px_r  <= 0;
		drv_col_r <= 0;
		drv_px_r  <= 0;
	end else if (ce) begin
		if (x_pos == 32-1) begin
			dbg_col_r <= 0;
			dbg_px_r  <= 0;
		end else if (dbg_area) begin
			if (dbg_px_r == 5) begin
				dbg_px_r  <= 0;
				dbg_col_r <= dbg_col_r + 1'd1;
			end else begin
				dbg_px_r  <= dbg_px_r + 1'd1;
			end
		end

		if (x_pos == base_x - 10'd1) begin
			drv_col_r <= 0;
			drv_px_r  <= 0;
		end else if (drv_area) begin
			if (drv_px_r == 5) begin
				drv_px_r  <= 0;
				drv_col_r <= drv_col_r + 1'd1;
			end else begin
				drv_px_r  <= drv_px_r + 1'd1;
			end
		end
	end
end

always @(posedge clk) begin
	if (vblank) begin
		dbg_row_r <= 0;
		dbg_py_r  <= 0;
		drv_row_r <= 0;
		drv_py_r  <= 0;
	end else if (ce) begin
		if (old_hblank && ~hblank) begin
			if (y_pos == 32-1) begin
				dbg_row_r <= 0;
				dbg_py_r  <= 0;
			end else if (dbg_area || (y_pos >= 32 && y_pos < 32 + 17*6)) begin
				if (dbg_py_r == 5) begin
					dbg_py_r  <= 0;
					dbg_row_r <= dbg_row_r + 1'd1;
				end else begin
					dbg_py_r  <= dbg_py_r + 1'd1;
				end
			end else begin
				dbg_row_r <= 0;
				dbg_py_r  <= 0;
			end

			if (y_pos == base_y-1) begin
				drv_row_r <= 0;
				drv_py_r  <= 0;
			end else if (drv_area || (y_pos >= base_y && y_pos < base_y + 12)) begin
				if (drv_py_r == 5) begin
					drv_py_r  <= 0;
					drv_row_r <= drv_row_r + 1'd1;
				end else begin
					drv_py_r  <= drv_py_r + 1'd1;
				end
			end else begin
				drv_row_r <= 0;
				drv_py_r  <= 0;
			end
		end
	end
end

wire [5:0] dbg_col = dbg_col_r;
wire [4:0] dbg_row = dbg_row_r;
wire [2:0] dbg_px  = dbg_px_r;
wire [2:0] dbg_py  = dbg_py_r;

wire [2:0] drv_col = drv_col_r;
wire       drv_row = drv_row_r;
wire [2:0] drv_px  = drv_px_r;
wire [2:0] drv_py  = drv_py_r;


// ---------------------------------------------------------------------------
// DATA RESOLUTION (COMBINATORIAL)
// ---------------------------------------------------------------------------

reg [63:0] src_data;
reg [3:0]  dbg_nibble;
reg [3:0]  nibble_idx;

always @(*) begin
	dbg_nibble = 4'h0;
	src_data   = 64'd0;
	nibble_idx = 4'd0;

	if (dbg_col < 51) begin
		if (dbg_row < 8) begin
			if (dbg_col < 8) begin
				src_data   = {32'd0, hist_addr[dbg_row[2:0]]};
				nibble_idx = 4'(7 - dbg_col);
			end else if (dbg_col > 8 && dbg_col < 25) begin
				src_data   = hist_data[dbg_row[2:0]];
				nibble_idx = 4'(24 - dbg_col);
			end else if (dbg_col >= 26 && dbg_col < 34) begin
				src_data   = {32'd0, wr_hist_addr[dbg_row[2:0]]};
				nibble_idx = 4'(33 - dbg_col);
			end else if (dbg_col > 34 && dbg_col < 51) begin
				src_data   = wr_hist_data[dbg_row[2:0]];
				nibble_idx = 4'(50 - dbg_col);
			end
		end else if (dbg_row >= 9 && dbg_row < 17) begin
			if (dbg_col < 8) begin
				src_data   = {32'd0, base_addr + (dbg_row - 5'd9)};
				nibble_idx = 4'(7 - dbg_col);
			end else if (dbg_col > 8 && dbg_col < 25) begin
				src_data   = snoop_data[dbg_row[2:0] - 3'd1];
				nibble_idx = 4'(24 - dbg_col);
			end else if (dbg_col >= 26 && dbg_col < 34) begin
				src_data   = {32'd0, base_addr + (dbg_row - 5'd9)};
				nibble_idx = 4'(33 - dbg_col);
			end else if (dbg_col > 34 && dbg_col < 51) begin
				src_data   = wr_snoop_data[dbg_row[2:0] - 3'd1];
				nibble_idx = 4'(50 - dbg_col);
			end
		end

		if (dbg_col != 8 && dbg_col != 25 && dbg_col != 34) begin
			dbg_nibble = src_data[(nibble_idx * 4) +: 4];
		end
	end
end

wire active_row = (dbg_row < 8) || (dbg_row >= 9 && dbg_row < 17);
wire valid_pixel_rd = dbg_area && active_row && debug_active && (dbg_px < 5) && (dbg_py < 5) && (dbg_col < 25) && (dbg_col != 8);
wire valid_pixel_wr = dbg_area && active_row && debug_active && (dbg_px < 5) && (dbg_py < 5) && (dbg_col >= 26) && (dbg_col < 51) && (dbg_col != 34);

reg [4:0]  drv_char;
wire [6:0] drv_track  = drv_row ? drive_track_1 : drive_track_0;
wire [6:0] full_track = (drv_track >> 1) + 7'd1;
wire       half_track = drv_track[0];

wire [3:0] track_tens = (full_track >= 80) ? 4'd8 : (full_track >= 70) ? 4'd7 : (full_track >= 60) ? 4'd6 :
                        (full_track >= 50) ? 4'd5 : (full_track >= 40) ? 4'd4 : (full_track >= 30) ? 4'd3 :
                        (full_track >= 20) ? 4'd2 : (full_track >= 10) ? 4'd1 : 4'd0;
wire [3:0] track_ones = 4'(full_track - ((track_tens << 3) + (track_tens << 1)));

always @(*) begin
	case (drv_col)
		0: drv_char = 5'h10; // '#'
		1: drv_char = drv_row ? 5'h09 : 5'h08; // '9' or '8'
		2: drv_char = 5'h11; // ' '
		3: drv_char = (track_tens == 0) ? 5'h11 : {1'b0, track_tens};
		4: drv_char = {1'b0, track_ones};
		5: drv_char = half_track ? 5'h12 : 5'h11; // '.' or ' '
		6: drv_char = half_track ? 5'h05 : 5'h11; // '5' or ' '
		default: drv_char = 5'h11;
	endcase
end

wire drv_led_act     = drive_led[drv_row];
wire drv_we_act      = drive_we[drv_row];
wire valid_osd_pixel = drv_area && (drv_px < 5) && (drv_py < 5) &&
					   ((drive_osd_mode == 0 && drv_led_act) ||
					   (drive_osd_mode == 1 && drive_mounted[drv_row]) ||
					   drive_osd_mode == 2);


// ---------------------------------------------------------------------------
// PIPELINE STAGE 1: Latch coordinates, character inputs, and state flags
// ---------------------------------------------------------------------------
reg [4:0] char_to_draw_s1;
reg [2:0] px_s1;
reg [2:0] py_s1;

reg valid_osd_s1, valid_rd_s1, valid_wr_s1;
reg drv_led_act_s1, drv_we_act_s1;

always @(posedge clk) begin
	if (ce) begin
		char_to_draw_s1 <= valid_osd_pixel ? drv_char : {1'b0, dbg_nibble};
		px_s1           <= valid_osd_pixel ? drv_px   : dbg_px;
		py_s1           <= valid_osd_pixel ? drv_py   : dbg_py;

		valid_osd_s1    <= valid_osd_pixel;
		valid_rd_s1     <= valid_pixel_rd;
		valid_wr_s1     <= valid_pixel_wr;
		drv_led_act_s1  <= drv_led_act;
		drv_we_act_s1   <= drv_we_act;
	end
end


// ---------------------------------------------------------------------------
// PIPELINE STAGE 2: Font ROM Lookup
// ---------------------------------------------------------------------------
reg [4:0] font_row_s2;
reg [2:0] px_s2;

reg valid_osd_s2, valid_rd_s2, valid_wr_s2;
reg drv_led_act_s2, drv_we_act_s2;

always @(posedge clk) begin
	if (ce) begin
		// Font Lookup
		case (char_to_draw_s1)
			5'h00: case(py_s1) 0: font_row_s2<=5'b01110; 1: font_row_s2<=5'b10001; 2: font_row_s2<=5'b10001; 3: font_row_s2<=5'b10001; 4: font_row_s2<=5'b01110; default: font_row_s2<=0; endcase
			5'h01: case(py_s1) 0: font_row_s2<=5'b00100; 1: font_row_s2<=5'b01100; 2: font_row_s2<=5'b00100; 3: font_row_s2<=5'b00100; 4: font_row_s2<=5'b01110; default: font_row_s2<=0; endcase
			5'h02: case(py_s1) 0: font_row_s2<=5'b01110; 1: font_row_s2<=5'b10001; 2: font_row_s2<=5'b00110; 3: font_row_s2<=5'b01000; 4: font_row_s2<=5'b11111; default: font_row_s2<=0; endcase
			5'h03: case(py_s1) 0: font_row_s2<=5'b11110; 1: font_row_s2<=5'b00001; 2: font_row_s2<=5'b01110; 3: font_row_s2<=5'b00001; 4: font_row_s2<=5'b11110; default: font_row_s2<=0; endcase
			5'h04: case(py_s1) 0: font_row_s2<=5'b10001; 1: font_row_s2<=5'b10001; 2: font_row_s2<=5'b11111; 3: font_row_s2<=5'b00001; 4: font_row_s2<=5'b00001; default: font_row_s2<=0; endcase
			5'h05: case(py_s1) 0: font_row_s2<=5'b11111; 1: font_row_s2<=5'b10000; 2: font_row_s2<=5'b11110; 3: font_row_s2<=5'b00001; 4: font_row_s2<=5'b11110; default: font_row_s2<=0; endcase
			5'h06: case(py_s1) 0: font_row_s2<=5'b01110; 1: font_row_s2<=5'b10000; 2: font_row_s2<=5'b11110; 3: font_row_s2<=5'b10001; 4: font_row_s2<=5'b01110; default: font_row_s2<=0; endcase
			5'h07: case(py_s1) 0: font_row_s2<=5'b11111; 1: font_row_s2<=5'b00001; 2: font_row_s2<=5'b00010; 3: font_row_s2<=5'b00100; 4: font_row_s2<=5'b00100; default: font_row_s2<=0; endcase
			5'h08: case(py_s1) 0: font_row_s2<=5'b01110; 1: font_row_s2<=5'b10001; 2: font_row_s2<=5'b01110; 3: font_row_s2<=5'b10001; 4: font_row_s2<=5'b01110; default: font_row_s2<=0; endcase
			5'h09: case(py_s1) 0: font_row_s2<=5'b01110; 1: font_row_s2<=5'b10001; 2: font_row_s2<=5'b01111; 3: font_row_s2<=5'b00001; 4: font_row_s2<=5'b01110; default: font_row_s2<=0; endcase
			5'h0A: case(py_s1) 0: font_row_s2<=5'b01110; 1: font_row_s2<=5'b10001; 2: font_row_s2<=5'b11111; 3: font_row_s2<=5'b10001; 4: font_row_s2<=5'b10001; default: font_row_s2<=0; endcase
			5'h0B: case(py_s1) 0: font_row_s2<=5'b11110; 1: font_row_s2<=5'b10001; 2: font_row_s2<=5'b11110; 3: font_row_s2<=5'b10001; 4: font_row_s2<=5'b11110; default: font_row_s2<=0; endcase
			5'h0C: case(py_s1) 0: font_row_s2<=5'b01110; 1: font_row_s2<=5'b10000; 2: font_row_s2<=5'b10000; 3: font_row_s2<=5'b10000; 4: font_row_s2<=5'b01110; default: font_row_s2<=0; endcase
			5'h0D: case(py_s1) 0: font_row_s2<=5'b11110; 1: font_row_s2<=5'b10001; 2: font_row_s2<=5'b10001; 3: font_row_s2<=5'b10001; 4: font_row_s2<=5'b11110; default: font_row_s2<=0; endcase
			5'h0E: case(py_s1) 0: font_row_s2<=5'b11111; 1: font_row_s2<=5'b10000; 2: font_row_s2<=5'b11110; 3: font_row_s2<=5'b10000; 4: font_row_s2<=5'b11111; default: font_row_s2<=0; endcase
			5'h0F: case(py_s1) 0: font_row_s2<=5'b11111; 1: font_row_s2<=5'b10000; 2: font_row_s2<=5'b11110; 3: font_row_s2<=5'b10000; 4: font_row_s2<=5'b10000; default: font_row_s2<=0; endcase
			5'h10: case(py_s1) 0: font_row_s2<=5'b01010; 1: font_row_s2<=5'b11111; 2: font_row_s2<=5'b01010; 3: font_row_s2<=5'b11111; 4: font_row_s2<=5'b01010; default: font_row_s2<=0; endcase // '#'
			5'h11: case(py_s1) 0: font_row_s2<=5'b00000; 1: font_row_s2<=5'b00000; 2: font_row_s2<=5'b00000; 3: font_row_s2<=5'b00000; 4: font_row_s2<=5'b00000; default: font_row_s2<=0; endcase // ' '
			5'h12: case(py_s1) 0: font_row_s2<=5'b00000; 1: font_row_s2<=5'b00000; 2: font_row_s2<=5'b00000; 3: font_row_s2<=5'b01100; 4: font_row_s2<=5'b01100; default: font_row_s2<=0; endcase // '.'
			default: font_row_s2<=0;
		endcase

		// Forward state
		px_s2          <= px_s1;
		valid_osd_s2   <= valid_osd_s1;
		valid_rd_s2    <= valid_rd_s1;
		valid_wr_s2    <= valid_wr_s1;
		drv_led_act_s2 <= drv_led_act_s1;
		drv_we_act_s2  <= drv_we_act_s1;
	end
end


// ---------------------------------------------------------------------------
// PIPELINE STAGE 3: Final Pixel Shift and Color Mixing
// ---------------------------------------------------------------------------
wire [2:0] px_rev = (px_s2 < 5) ? 3'd4 - px_s2 : 3'd0;
wire pixel_base   = (px_s2 < 5) ? font_row_s2[px_rev] : 1'b0;

reg [1:0] pixel_color_out;

always @(posedge clk) begin
	if (ce) begin
		if (valid_osd_s2 && pixel_base && drv_led_act_s2 && drv_we_act_s2) begin
			pixel_color_out <= 2'd3; // Red (Drive Write)
		end else if ((valid_osd_s2 && pixel_base && drv_led_act_s2 && ~drv_we_act_s2) || (valid_wr_s2 && pixel_base)) begin
			pixel_color_out <= 2'd2; // Yellow (Drive Read or Debug Write)
		end else if ((valid_osd_s2 && pixel_base && ~drv_led_act_s2) || (valid_rd_s2 && pixel_base)) begin
			pixel_color_out <= 2'd1; // Green (Drive Idle or Debug Read)
		end else begin
			pixel_color_out <= 2'd0; // Transparent
		end
	end
end

assign pixel_color = pixel_color_out;

endmodule
