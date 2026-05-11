//-------------------------------------------------------------------------------
//
// Reworked and adapted to MiSTer by Sorgelig@MiSTer (07.09.2018)
//
// Commodore 1541 to SD card by Dar (darfpga@aol.fr)
// http://darfpga.blogspot.fr
//
// c1541_logic    from : Mark McDougall
// via6522        from : Gideon Zweijtzer  <gideon.zweijtzer@gmail.com>
// c1541_track    from : Sorgelig@MiSTer
//
// c1541_logic    modified for : slow down CPU (EOI ack missed by real c64)
//                             : remove iec internal OR wired
//                             : synched atn_in (sometime no IRQ with real c64)
//
// Input clk ~32MHz (clk_sys from top level, previously labeled 16MHz)
//
//-------------------------------------------------------------------------------

module c1541_drv
(
	//clk ports
	input         clk,
	input         reset,

	input         gcr_mode,

	input         ce,
	input         ph2_r,
	input         ph2_f,

	input         img_mounted,
	input         img_readonly,
	input  [31:0] img_size,
	input   [2:0] drive_rpm,
	input         drive_wobble,

	output reg    disk_ready,

	input   [1:0] drive_num,
	output        led,
	output wire [6:0] out_track,
	output wire    out_we,

	input         iec_atn_i,
	input         iec_data_i,
	input         iec_clk_i,
	output        iec_data_o,
	output        iec_clk_o,

	// parallel bus
	input   [7:0] par_data_i,
	input         par_stb_i,
	output  [7:0] par_data_o,
	output        par_stb_o,

	input         ext_en,
	output [14:0] rom_addr,
	input   [7:0] rom_data,

	//clk_sys ports
	input         clk_sys,

	output [31:0] sd_lba,
	output  [5:0] sd_blk_cnt,
	output        sd_rd,
	output        sd_wr,
	input         sd_ack,
	input  [13:0] sd_buff_addr,
	input   [7:0] sd_buff_dout,
	output  [7:0] sd_buff_din,
	input         sd_buff_wr,

	input         DDRAM_BUSY,
	output  [7:0] DDRAM_BURSTCNT,
	output [28:0] DDRAM_ADDR,
	input  [63:0] DDRAM_DOUT,
	input         DDRAM_DOUT_READY,
	output        DDRAM_RD,
	output        DDRAM_WE,
	output [63:0] DDRAM_DIN,
	output  [7:0] DDRAM_BE
);

assign led       = act;
assign out_track = track;
assign out_we    = track_modified | busy_flushing_s;

reg        readonly     = 0;
reg        disk_present = 0;
reg [24:0] ch_timeout;
always @(posedge clk) begin
	reg old_mounted;
	reg present = 0;

	if(ce && ch_timeout > 0) ch_timeout <= ch_timeout - 1'd1;
	if(!ch_timeout) disk_present <= present;
	disk_ready <= !ch_timeout;

	old_mounted <= img_mounted;
	if (~old_mounted & img_mounted) begin
		ch_timeout <= '1;
		readonly <= img_readonly;
		present <= |img_size;
		disk_present <= 0;
	end
end

wire       mode; // read/write
wire [1:0] stp;
wire       mtr;
wire       act;
wire [1:0] freq;
wire       wps_n = ~readonly ^ ch_timeout[23];

c1541_logic c1541_logic
(
	.clk(clk),
	.reset(reset),

	.ce(ce),
	.ph2_r(ph2_r),
	.ph2_f(ph2_f),

	// serial bus
	.iec_clk_in(iec_clk_i),
	.iec_data_in(iec_data_i),
	.iec_atn_in(iec_atn_i),
	.iec_clk_out(iec_clk_o),
	.iec_data_out(iec_data_o),

	.ext_en(ext_en),
	.rom_addr(rom_addr),
	.rom_data(rom_data),

	// parallel bus
	.par_data_in(par_data_i),
	.par_stb_in(par_stb_i),
	.par_data_out(par_data_o),
	.par_stb_out(par_stb_o),

	// drive-side interface
	.ds(drive_num),
	.din(dgcr_do),
	.dout(dgcr_di),
	.mode(mode),
	.stp(stp),
	.mtr(mtr),
	.freq(freq),
	.sync_n(dgcr_sync_n),
	.byte_n(dgcr_byte_n),
	.wps_n(wps_n),
	.tr00_sense_n(|track),
	.act(act)
);

iecdrv_sync dirty_sync(clk, busy_flushing, busy_flushing_s);
wire        we = dgcr_we;
wire [7:0]  dgcr_do,dgcr_di;
wire [63:0] dgcr_sd_buff_dout;
wire        dgcr_sync_n, dgcr_byte_n, dgcr_we;
wire [13:0] dma_buff_addr;
wire [63:0] dma_buff_dout;
wire        dma_buff_wr;
wire        dma_active;

// Interface bg_buff (64bit) to sd_buff (8bit)
wire [63:0] bg_buff_dout;
assign      sd_buff_din = bg_buff_dout[(sd_buff_addr[2:0]*8) +: 8];

c1541_direct_gcr c1541_direct_gcr
(
	.clk(clk),
	.ce(ce & gcr_mode),
	.reset(reset),
	
	.drive_rpm(drive_rpm),
	.drive_wobble(drive_wobble),
	
	.dout(dgcr_do),
	.din(dgcr_di),
	.mode(mode),
	.mtr(mtr),
	.freq(freq),
	.wps_n(wps_n),
	.sync_n(dgcr_sync_n),
	.byte_n(dgcr_byte_n),

	.disk_present(disk_present),
	.we(dgcr_we),

	.sd_clk(clk_sys),
	.sd_buff_addr(dma_buff_addr),
	.sd_buff_dout(dma_buff_dout),
	.sd_buff_din(dgcr_sd_buff_dout),
	.sd_buff_wr(dma_buff_wr)
);

wire busy_flushing;
wire busy_flushing_s;

c1541_track c1541_track
(
	.clk(clk_sys),
	.reset(reset),

	.gcr_mode(gcr_mode),

	.sd_lba(sd_lba),
	.sd_blk_cnt(sd_blk_cnt),
	.sd_rd(sd_rd),
	.sd_wr(sd_wr),
	.sd_ack(sd_ack),

	.save_track(save_track),
	.change(img_mounted),
	.track(track),
	.busy_flushing(busy_flushing),
	.drive_num(drive_num[0]),

	.DDRAM_BUSY(DDRAM_BUSY),
	.DDRAM_BURSTCNT(DDRAM_BURSTCNT),
	.DDRAM_ADDR(DDRAM_ADDR),
	.DDRAM_DOUT(DDRAM_DOUT),
	.DDRAM_DOUT_READY(DDRAM_DOUT_READY),
	.DDRAM_RD(DDRAM_RD),
	.DDRAM_WE(DDRAM_WE),
	.DDRAM_DIN(DDRAM_DIN),
	.DDRAM_BE(DDRAM_BE),

	.dma_buff_addr(dma_buff_addr),
	.dma_buff_dout(dma_buff_dout),
	.dma_buff_wr(dma_buff_wr),
	.dma_buff_din(dgcr_sd_buff_dout),

	.sd_buff_addr(sd_buff_addr),
	.bg_buff_dout(bg_buff_dout)
);

reg [6:0] track;
reg       save_track = 0;
reg [23:0] read_timer = 0;
reg        track_modified = 0;
always @(posedge clk) begin
	reg [6:0] track_num;
	reg [1:0] move, stp_old;

	track <= track_num;

	stp_old <= stp;
	move <= stp - stp_old;

	if (we && disk_present) track_modified <= 1;
	if (img_mounted)        track_modified <= 0;

	if (reset) begin
		track_num <= 34;
		track_modified <= 0;
	end else begin
		if (mtr & move[0]) begin
			if (~move[1] && track_num < 84) track_num <= track_num + 1'b1;
			if ( move[1] && track_num > 0 ) track_num <= track_num - 1'b1;
			// must save modified track on track change
			if (track_modified) save_track <= ~save_track;
			track_modified <= 0;
		end

		// Save Track Strategy:
		// balance SD longevity against data integrity by aggregating writes.
		//
		// Trade-offs:
		// - DOS motor-off is too sluggish (~2s) for modern users.
		// - DOS write-patterns (sector-by-sector) cause 20+ cycles per track.
		// - Poorly behaved software (e.g., track copiers) abuses the LED and motor states.
		//
		// Strategy:
		// We use a Write->Read transition timeout. If the drive has been in read mode for
		// ~500ms since the last write, we assume inactivity and save the track.
		// We also save immediately if the motor turns off.
		if (track_modified && ((mode && read_timer == 24'd16_000_000) || !mtr)) begin
			save_track <= ~save_track;
			track_modified <= 0;
		end
	end

	// Timer for read inactivity (500ms at ~32MHz = 16,000,000 cycles)
	if (!mode) begin // mode 0 = writing
		read_timer <= 0;
	end else if (read_timer != 24'd16_000_000) begin
		read_timer <= read_timer + 1'd1;
	end

end

endmodule
