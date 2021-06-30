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
// Input clk 16MHz
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

	input   [1:0] drive_num,
	output        led,

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
	input         sd_buff_wr
);

assign led = act | sd_busy;

reg        readonly = 0;
reg        disk_present = 0;
reg [23:0] ch_timeout;
always @(posedge clk) begin
	reg old_mounted;

	if(ce && ch_timeout > 0) ch_timeout <= ch_timeout - 1'd1;

	old_mounted <= img_mounted;
	if (~old_mounted & img_mounted) begin
		ch_timeout <= '1;
		readonly <= img_readonly;
		disk_present <= |img_size;
	end
end

wire       mode; // read/write
wire [1:0] stp;
wire       mtr;
wire       act;
wire [1:0] freq;

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
	.din(gcr_mode ? dgcr_do : gcr_do),
	.dout(gcr_di),
	.mode(mode),
	.stp(stp),
	.mtr(mtr),
	.freq(freq),
	.sync_n(gcr_mode ? dgcr_sync_n : gcr_sync_n),
	.byte_n(gcr_mode ? dgcr_byte_n : gcr_byte_n),
	.wps_n(~readonly ^ ch_timeout[22]),
	.tr00_sense_n(|track),
	.act(act)
);

wire  [7:0] gcr_di;
wire        we = gcr_mode ? dgcr_we : gcr_we;
assign      sd_buff_din = gcr_mode ? dgcr_sd_buff_dout : gcr_sd_buff_dout;

wire sd_busy;
iecdrv_sync busy_sync(clk, busy, sd_busy);

wire [7:0]  gcr_do, gcr_sd_buff_dout;
wire        gcr_sync_n, gcr_byte_n, gcr_we;

c1541_gcr c1541_gcr
(
	.clk(clk),
	.ce(ce & ~gcr_mode),
	
	.dout(gcr_do),
	.din(gcr_di),
	.mode(mode),
	.mtr(mtr),
	.freq(freq),
	.sync_n(gcr_sync_n),
	.byte_n(gcr_byte_n),

	.track(track[6:1]+1'd1),
	.busy(sd_busy | ~disk_present),
	.we(gcr_we),

	.sd_clk(clk_sys),
	.sd_lba(sd_lba),
	.sd_buff_addr(sd_buff_addr[12:0]),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(gcr_sd_buff_dout),
	.sd_buff_wr(sd_ack & sd_buff_wr & ~gcr_mode)
);

wire [7:0] dgcr_do, dgcr_sd_buff_dout;
wire       dgcr_sync_n, dgcr_byte_n, dgcr_we;

c1541_direct_gcr c1541_direct_gcr
(
	.clk(clk),
	.ce(ce & gcr_mode),
	.reset(reset),
	
	.dout(dgcr_do),
	.din(gcr_di),
	.mode(mode),
	.mtr(mtr),
	.freq(freq),
	.sync_n(dgcr_sync_n),
	.byte_n(dgcr_byte_n),

	.busy(sd_busy | ~disk_present),
	.we(dgcr_we),

	.sd_clk(clk_sys),
	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(dgcr_sd_buff_dout),
	.sd_buff_wr(sd_ack & sd_buff_wr & gcr_mode)
);

wire busy;

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
	.busy(busy)
);

reg [6:0] track;
reg       save_track = 0;
always @(posedge clk) begin
	reg       track_modified;
	reg [6:0] track_num;
	reg [1:0] move, stp_old;

	track <= track_num;

	stp_old <= stp;
	move <= stp - stp_old;

	if (we)          track_modified <= 1;
	if (img_mounted) track_modified <= 0;

	if (reset) begin
		track_num <= 36;
		track_modified <= 0;
	end else begin
		if (mtr & move[0]) begin
			if (~move[1] && track_num < 84) track_num <= track_num + 1'b1;
			if ( move[1] && track_num > 0 ) track_num <= track_num - 1'b1;
			if (track_modified) save_track <= ~save_track;
			track_modified <= 0;
		end

		if (track_modified & ~act) begin	// stopping activity
			save_track <= ~save_track;
			track_modified <= 0;
		end
	end
end

endmodule
