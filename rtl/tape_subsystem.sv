`timescale 1ns/1ps
// ============================================================================
// C1530 Datassette subsystem
//
// Keeps the top-level clean by grouping all TAP/Datasette related logic:
// - TAP load tracking and version capture
// - accurate TAP time-map scanner for FF/REW
// - counter -> TAP offset time map RAM
// - FF/REW/STOP/PLAY transport state
// - C1530 player instance
// - tape counter video overlay
//
// The actual SDRAM read port remains owned by c64.sv.  This module exposes
// tap_play_addr; c64.sv keeps using that address for the existing SDRAM TAP
// prefetch cycle and feeds the returned byte back through sdram_data.
// ============================================================================

module tape_subsystem (
	input         clk,
	input         ce,
	input         reset_n,
	input         hblank,
	input         vblank,
	input         ntsc,

	// TAP download/ioctl stream
	input         ioctl_download,
	input         ioctl_wr,
	input  [24:0] ioctl_addr,
	input   [7:0] ioctl_data,
	input         load_tap,
	output        ioctl_wait,

	// Existing SDRAM TAP prefetch timing/data from top-level
	input         io_cycle,
	input   [7:0] sdram_data,

	// OSD/key transport controls. Inputs are pulses except counter_enable.
	input         osd_play,
	input         osd_stop,
	input         osd_rew,
	input         osd_ff,
	input         cmd_unload,
	input         osd_counter_reset,
	input         key_play,
	input         key_stop,
	input         key_rew,
	input         key_ff,
	input         key_counter_reset,
	input         counter_enable,
	input         tape_autoplay_off,
	input         tape_autounload_off,

	// C1530/C64 cassette lines
	input         cass_write,
	input         cass_motor,
	output reg    cass_sense,
	output        cass_read,
	output        cass_run,
	output        cass_finish,

	// Status back to top-level
	output        tap_loaded,
	output [24:0] tap_play_addr,
	output [24:0] tap_last_addr,

	// Overlay color: 0=transparent, 1=green, 2=yellow, 3=red, 4=blue
	output [2:0]  pixel_color
);

wire       tap_download = ioctl_download & load_tap;
wire       tap_reset;
wire       tap_at_end;

reg        tap_ready_gated;
wire       tap_ready;

reg [24:0] tap_play_addr_r;
reg [24:0] tap_last_addr_r;
assign tap_play_addr = tap_play_addr_r;
assign tap_last_addr = tap_last_addr_r;

assign tap_reset  = ~reset_n | tap_download | cmd_unload | !tap_last_addr_r | tape_end;
assign tap_loaded = (|tap_last_addr_r) && tap_ready_gated; // keep mounted at end-of-tape
assign tap_at_end = tap_loaded && (tap_play_addr_r >= tap_last_addr_r);

always @(posedge clk) begin
	if (tap_reset) tap_ready_gated <= 1'b0;
	else           tap_ready_gated <= tap_ready;
end

// Some hps_io/firmware versions leave OSD T-trigger bits high for multiple
// cycles, while keyboard shortcuts are already one-cycle pulses. Synthesize
// clean one-cycle command pulses from the OSD level inputs before combining.
reg osd_play_d = 0, osd_stop_d = 0, osd_rew_d = 0, osd_ff_d = 0, osd_counter_reset_d = 0;
always @(posedge clk) begin
	osd_play_d <= osd_play;
	osd_stop_d <= osd_stop;
	osd_rew_d  <= osd_rew;
	osd_ff_d   <= osd_ff;
	osd_counter_reset_d <= osd_counter_reset;
end
wire cmd_play = (osd_play & ~osd_play_d) | key_play;
wire cmd_stop = (osd_stop & ~osd_stop_d) | key_stop;
wire cmd_rew  = (osd_rew  & ~osd_rew_d)  | key_rew;
wire cmd_ff   = (osd_ff   & ~osd_ff_d)   | key_ff;
wire cmd_counter_reset = (osd_counter_reset & ~osd_counter_reset_d) | key_counter_reset;

// TAP version is needed by c1530 while playing back from SDRAM.
reg [1:0] tap_version;
always @(posedge clk) begin
	if (ioctl_wr && load_tap && ioctl_addr == 25'd12) begin
		tap_version <= ioctl_data[1:0];
	end
end

// --- TAP time map for accurate FF/REW ---
wire [12:0] tap_map_max;
wire [24:0] tap_map_wrdata;
wire [12:0] tap_map_wraddr;
wire        tap_map_wr;
wire [24:0] tap_map_rddata;
reg  [12:0] tap_map_rdaddr;
reg         tap_map_update;
reg         tap_map_update_d;

reg         old_tap_download;
wire        tap_download_start = ~old_tap_download & tap_download;
wire        tap_done = old_tap_download & ~tap_download;
wire        tap_scanner_wait;

always @(posedge clk) begin
	if (!reset_n) old_tap_download <= 1'b0;
	else          old_tap_download <= tap_download;
end
assign ioctl_wait = tap_download & tap_scanner_wait;

tap_scanner #(.THRESH_BASE(2693), .THRESH_INC(6), .ABS_MAX(8191), .MAP_AW(13)) tap_scanner
(
	.clk(clk),
	.reset_n(reset_n & ~tape_end & ~cmd_unload),
	.start(tap_download_start),
	.tap_wr(ioctl_wr & load_tap),
	.tap_addr(ioctl_addr),
	.tap_data(ioctl_data),
	.tap_done(tap_done),
	.map_wr(tap_map_wr),
	.map_addr(tap_map_wraddr),
	.map_data(tap_map_wrdata),
	.busy(),
	.ready(tap_ready),
	.map_max(tap_map_max),
	.wait_req(tap_scanner_wait)
);

tap_time_map #(.AW(13), .DW(25)) tap_time_map
(
	.clk(clk),
	.wr_addr(tap_map_wraddr),
	.wr_data(tap_map_wrdata),
	.wr_en(tap_map_wr),
	.rd_addr(tap_map_rdaddr),
	.rd_data(tap_map_rddata)
);

// --- Transport state shared by counter and C1530 feed control ---
reg        tape_ff  = 1'b0;
reg        tape_rew = 1'b0;
wire       tape_winding = tape_ff | tape_rew;

// --- Tape counter overlay ---
wire [12:0] tc_abs_count;
wire        tc_wind_step;

tape_counter #(.ABS_MAX(8191)) tape_counter
(
	.clk(clk),
	.ce(ce),
	.hblank(hblank),
	.vblank(vblank),
	.ntsc(ntsc),

	.enable(counter_enable),
	.tape_loaded(tap_loaded),
	.new_tape(tap_reset),
	.counter_reset(cmd_counter_reset),
	.tap_play_addr(tap_play_addr_r),
	.tap_last_addr(tap_last_addr_r),

	.cass_run(cass_run),
	.cass_sense(cass_sense),

	.ff(tape_ff),
	.rew(tape_rew),

	.wind_step(tc_wind_step),
	.abs_count(tc_abs_count),

	.pixel_color(pixel_color)
);

// --- Transport and C1530 feed control ---
// Pulses used to keep the C1530 FIFO aligned with seek operations.
reg        tape_seek_reset = 1'b0;

reg  [1:0] tap_wrreq;
wire       tap_wrfull;
reg        tape_end;

always @(posedge clk) begin
	reg io_cycleD;
	reg read_cyc;
	reg cmd_ff_d, cmd_rew_d, cmd_play_d, cmd_stop_d;
	
	cmd_ff_d <= cmd_ff;
	cmd_rew_d <= cmd_rew;
	cmd_play_d <= cmd_play;
	cmd_stop_d <= cmd_stop;

	io_cycleD <= io_cycle;
	tap_wrreq <= tap_wrreq << 1;
	tap_map_update_d <= tap_map_update;
	tap_map_update <= 1'b0;
	tape_seek_reset <= 1'b0;

	if (tap_reset) begin
		// c1530 requires one more byte at the end due to FIFO early check.
		tap_last_addr_r <= tap_download ? ioctl_addr + 2'd2 : 25'd0;
		tap_play_addr_r <= 25'd0;
		cass_sense      <= tape_autoplay_off | ~tap_download;
		read_cyc        <= 1'b0;
		tape_ff         <= 1'b0;
		tape_rew        <= 1'b0;
		tap_map_rdaddr  <= 13'd0;
		tap_map_update  <= 1'b0;
		tap_map_update_d<= 1'b0;
		tape_seek_reset <= 1'b0;
		tape_end        <= 1'b0;
	end else begin

		if (tap_loaded) begin

			// FF/REW
			if ((~cmd_ff_d && cmd_ff) || (~cmd_rew_d && cmd_rew))  begin
				tape_ff  <= 0;
				tape_rew <= 0;
				if(!tape_ff && !tape_rew) begin
					tape_ff  <= cmd_ff;
					tape_rew <= ~cmd_ff;
				end
			end

			// PLAY/STOP
			if ((~cmd_play_d && cmd_play) || (~cmd_stop_d && cmd_stop)) begin
				tape_ff  <= 0;
				tape_rew <= 0;
				cass_sense <= ~cass_sense | cmd_stop;
			end
		end

		// Auto-stop at tape bounds.
		if (tape_ff  && (tc_abs_count + 1'b1 >= tap_map_max)) tape_ff  <= 1'b0;
		if (tape_rew && !tc_abs_count) tape_rew <= 1'b0;
		
		// motor turned off near the end -> unload
		if (!tape_autounload_off && cass_run && (tc_abs_count >= tap_map_max - 5'd5)) tape_end <= 1;
		if (!tape_autounload_off && (tc_abs_count + 1'b1 >= tap_map_max) && !cass_sense) tape_end <= 1;

		if (tape_winding) begin
			read_cyc <= 1'b0;
			if (tc_wind_step) begin
				if (tape_ff && (tc_abs_count + 1'b1 < tap_map_max)) begin
					tap_map_rdaddr <= tc_abs_count + 1'b1;
					tap_map_update <= 1'b1;
				end else if (tape_rew && tc_abs_count) begin
					tap_map_rdaddr <= tc_abs_count - 1'b1;
					tap_map_update <= 1'b1;
				end
			end
		end else begin
			// Normal playback.  c64.sv already points the SDRAM TAP prefetch at
			// tap_play_addr_r; sdram_data is valid on the matching later phase.
			if (~io_cycle & io_cycleD & ~tap_wrfull & tap_loaded & ~tap_at_end) read_cyc <= 1'b1;
			if (io_cycle & io_cycleD & read_cyc) begin
				tap_play_addr_r <= tap_play_addr_r + 1'b1;
				read_cyc <= 1'b0;
				tap_wrreq[0] <= 1'b1;
			end
		end

		// BRAM read latency compensation. c1530 always skips the 20-byte TAP
		// header after a restart, and the SDRAM prefetch has already queued the
		// next byte when the seek reset is asserted. Seek the feeder 21 bytes before
		// the mapped token so playback resumes at the requested safe offset.
		if (tap_map_update_d) begin
			tap_play_addr_r <= (tap_map_rddata > 25'd21) ? (tap_map_rddata - 25'd21) : 25'd0;
			tape_seek_reset <= 1'b1;
		end
	end
end

c1530 c1530
(
	.clk32(clk),
	.restart_tape(tap_reset | tape_seek_reset),
	.wav_mode(1'b0),
	.tap_version(tap_version),
	.host_tap_in(sdram_data),
	.host_tap_wrreq(tap_wrreq[1]),
	.tap_fifo_wrfull(tap_wrfull),
	.tap_fifo_error(cass_finish),
	.cass_read(cass_read),
	.cass_write(cass_write),
	.cass_motor(cass_motor),
	.cass_sense(cass_sense),
	.cass_run(cass_run)
);

endmodule