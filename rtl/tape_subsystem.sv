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
	input         osd_unload,
	input         osd_counter_reset,
	input         counter_enable,
	input         tape_autoplay_off,

	input         key_play,
	input         key_stop,
	input         key_rew,
	input         key_ff,
	input         key_counter_reset,

	// C1530/C64 cassette lines
	input         cass_write,
	input         cass_motor,
	output        cass_sense,
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

assign tap_reset  = ~reset_n | tap_download | osd_unload | !tap_last_addr_r;
assign tap_loaded = (|tap_last_addr_r) && tap_ready_gated; // keep mounted at end-of-tape
assign tap_at_end = tap_loaded && (tap_play_addr_r >= tap_last_addr_r);

always @(posedge clk) begin
	if (tap_reset) tap_ready_gated <= 1'b0;
	else           tap_ready_gated <= tap_ready;
end

// TAP version is needed by c1530 while playing back from SDRAM.
reg [1:0] tap_version;
always @(posedge clk) begin
	if (!reset_n) begin
		tap_version <= 2'd0;
	end else if (ioctl_wr && load_tap && ioctl_addr == 25'd12) begin
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
	.reset_n(reset_n),
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
wire        tc_at_start;

tape_counter #(.ABS_MAX(8191)) tape_counter
(
	.clk(clk),
	.ce(ce),
	.reset_n(reset_n),
	.hblank(hblank),
	.vblank(vblank),
	.ntsc(ntsc),

	.enable(counter_enable),
	.tape_loaded(tap_loaded),
	.new_tape(tap_reset),
	.counter_reset(osd_counter_reset | key_counter_reset),
	.tap_play_addr(tap_play_addr_r),
	.tap_last_addr(tap_last_addr_r),

	.cass_run(cass_run),
	.cass_sense(cass_sense),

	.ff(tape_ff),
	.rew(tape_rew),

	.wind_step(tc_wind_step),
	.abs_count(tc_abs_count),
	.at_tape_start(tc_at_start),

	.pixel_color(pixel_color)
);

// --- Transport and C1530 feed control ---
// Pulses used to keep the C1530 FIFO aligned with seek operations.
reg        tape_stop_pulse = 1'b0;
reg        tape_seek_reset = 1'b0;

reg        osd_ff_d = 1'b0,   key_ff_d = 1'b0;
reg        osd_rew_d = 1'b0,  key_rew_d = 1'b0;
reg        osd_play_d = 1'b0, key_play_d = 1'b0;
reg        osd_stop_d = 1'b0, key_stop_d = 1'b0;
wire       osd_ff_change   = osd_ff   ^ osd_ff_d;
wire       osd_rew_change  = osd_rew  ^ osd_rew_d;
wire       osd_play_change = osd_play ^ osd_play_d;
wire       osd_stop_change = osd_stop ^ osd_stop_d;
localparam [19:0] OSD_CMD_LOCKOUT = 20'd640000; // 20 ms at 32 MHz
reg [19:0] osd_ff_lockout = 20'd0, osd_rew_lockout = 20'd0;
reg [19:0] osd_play_lockout = 20'd0, osd_stop_lockout = 20'd0;
wire       osd_ff_pulse   = osd_ff_change   & (osd_ff_lockout   == 20'd0);
wire       osd_rew_pulse  = osd_rew_change  & (osd_rew_lockout  == 20'd0);
wire       osd_play_pulse = osd_play_change & (osd_play_lockout == 20'd0);
wire       osd_stop_pulse = osd_stop_change & (osd_stop_lockout == 20'd0);
wire       key_ff_edge    = key_ff   & ~key_ff_d;
wire       key_rew_edge   = key_rew  & ~key_rew_d;
wire       ff_edge        = osd_ff_pulse   | key_ff_edge;
wire       rew_edge       = osd_rew_pulse  | key_rew_edge;
wire       play_edge      = osd_play_pulse | (key_play & ~key_play_d);
wire       stop_edge      = osd_stop_pulse | (key_stop & ~key_stop_d);
reg  [1:0] tap_wrreq;
wire       tap_wrfull;
reg        tap_start;
reg        tape_play_pulse = 1'b0;

always @(posedge clk) begin
	reg io_cycleD;
	reg read_cyc;

	io_cycleD <= io_cycle;
	tap_wrreq <= tap_wrreq << 1;
	tap_map_update_d <= tap_map_update;
	tap_map_update <= 1'b0;
	tape_stop_pulse <= 1'b0;
	tape_seek_reset <= 1'b0;
	tape_play_pulse <= 1'b0;

	// OSD command bits may produce a set/clear pair for one selection.  Detect
	// level changes, then lock out the matching return edge so one selection maps
	// to one transport command. Keyboard commands remain one-shot rising pulses.
	if (osd_ff_lockout   != 20'd0) osd_ff_lockout   <= osd_ff_lockout   - 20'd1;
	if (osd_rew_lockout  != 20'd0) osd_rew_lockout  <= osd_rew_lockout  - 20'd1;
	if (osd_play_lockout != 20'd0) osd_play_lockout <= osd_play_lockout - 20'd1;
	if (osd_stop_lockout != 20'd0) osd_stop_lockout <= osd_stop_lockout - 20'd1;
	if (tap_loaded && osd_ff_pulse)   osd_ff_lockout   <= OSD_CMD_LOCKOUT;
	if (tap_loaded && osd_rew_pulse)  osd_rew_lockout  <= OSD_CMD_LOCKOUT;
	if (tap_loaded && osd_play_pulse) osd_play_lockout <= OSD_CMD_LOCKOUT;
	if (tap_loaded && osd_stop_pulse) osd_stop_lockout <= OSD_CMD_LOCKOUT;

	osd_ff_d   <= osd_ff;
	key_ff_d   <= key_ff;
	osd_rew_d  <= osd_rew;
	key_rew_d  <= key_rew;
	osd_play_d <= osd_play;
	key_play_d <= key_play;
	osd_stop_d <= osd_stop;
	key_stop_d <= key_stop;

	if (tap_reset) begin
		// c1530 requires one more byte at the end due to FIFO early check.
		tap_last_addr_r <= tap_download ? ioctl_addr + 2'd2 : 25'd0;
		tap_play_addr_r <= 25'd0;
		tap_start       <= ~tape_autoplay_off & tap_download;
		read_cyc        <= 1'b0;
		tape_ff         <= 1'b0;
		tape_rew        <= 1'b0;
		tap_map_rdaddr  <= 13'd0;
		tap_map_update  <= 1'b0;
		tap_map_update_d <= 1'b0;
		tape_stop_pulse <= 1'b0;
		tape_seek_reset <= 1'b0;
		tape_play_pulse <= 1'b0;
		osd_ff_d <= osd_ff;
		osd_rew_d <= osd_rew;
		osd_play_d <= osd_play;
		osd_stop_d <= osd_stop;
		osd_ff_lockout <= 20'd0;
		osd_rew_lockout <= 20'd0;
		osd_play_lockout <= 20'd0;
		osd_stop_lockout <= 20'd0;
	end else begin
		tap_start <= 1'b0;

		// At physical end keep the TAP mounted, but release PLAY once so the
		// Datassette state becomes STOP instead of auto-unloading the image.
		if (tap_at_end && ~cass_sense) begin
			tape_ff <= 1'b0;
			tape_rew <= 1'b0;
			tape_stop_pulse <= 1'b1;
		end

		// FF/REW commands select a transport direction. OSD events are treated as
		// start commands so a possible OSD set/clear pair cannot cancel itself.
		// Keyboard shortcuts keep the previous toggle behavior.
		if (tap_loaded && ff_edge) begin
			tape_ff  <= osd_ff_pulse ? 1'b1 : ~tape_ff;
			tape_rew <= 1'b0;
			if (~cass_sense) tape_stop_pulse <= 1'b1;
		end

		if (tap_loaded && rew_edge) begin
			tape_rew <= osd_rew_pulse ? 1'b1 : ~tape_rew;
			tape_ff  <= 1'b0;
			if (~cass_sense) tape_stop_pulse <= 1'b1;
		end

		// PLAY stops winding.
		if (tap_loaded && play_edge) begin
			tape_ff  <= 1'b0;
			tape_rew <= 1'b0;
			tape_play_pulse <= 1'b1;
		end

		// STOP stops winding and forces C1530 to STOP if PLAY is pressed.
		if (tap_loaded && stop_edge) begin
			tape_ff  <= 1'b0;
			tape_rew <= 1'b0;
			if (~cass_sense) tape_stop_pulse <= 1'b1;
		end

		// Auto-stop at tape bounds.
		if (tape_ff  && (tc_abs_count + 1'b1 >= tap_map_max)) tape_ff  <= 1'b0;
		if (tape_rew && tc_at_start) tape_rew <= 1'b0;

		if (tape_winding) begin
			read_cyc <= 1'b0;
			if (tc_wind_step) begin
				if (tape_ff && (tc_abs_count + 1'b1 < tap_map_max)) begin
					tap_map_rdaddr <= tc_abs_count + 1'b1;
					tap_map_update <= 1'b1;
				end else if (tape_rew && !tc_at_start) begin
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
	.cass_run(cass_run),
	.osd_play_stop_toggle(tape_play_pulse | tap_start | tape_stop_pulse),
	.ear_input(1'b0)
);

endmodule