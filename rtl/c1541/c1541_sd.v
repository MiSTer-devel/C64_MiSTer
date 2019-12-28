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
// Input clk 32MHz
//
//-------------------------------------------------------------------------------

module c1541_sd
(
	//clk_c1541 ports
	input         clk_c1541,

	input         disk_change,
	input         disk_readonly,
	input   [1:0] drive_num,
	output        led,

	input         iec_reset_i,
	input         iec_atn_i,
	input         iec_data_i,
	input         iec_clk_i,
	output        iec_data_o,
	output        iec_clk_o,

	//clk_sys ports
	input         clk_sys,

	output [31:0] sd_lba,
	output        sd_rd,
	output        sd_wr,
	input         sd_ack,
	input   [8:0] sd_buff_addr,
	input   [7:0] sd_buff_dout,
	output  [7:0] sd_buff_din,
	input         sd_buff_wr,
	output        sd_busy,

	input  [13:0] rom_addr,
	input   [7:0] rom_data,
	input         rom_wr,
	input         stdrom_wr,
	input         rom_std
);

assign led = act | sd_busy;

// Force reload as disk may have changed
// Track number (0-34)
// Sector number (0-20)

reg reset;
always @(posedge clk_c1541) begin
	reg reset_r;
	reset_r <= iec_reset_i;
	reset <= reset_r;
end

reg readonly = 0;
reg ch_state;
always @(posedge clk_c1541) begin
	integer ch_timeout;
	reg     prev_change;

	prev_change <= disk_change;
	if (ch_timeout > 0) begin
		ch_timeout <= ch_timeout - 1;
		ch_state <= 1;
	end else ch_state <= 0;
	if (~prev_change & disk_change) begin
		ch_timeout <= 15000000;
		readonly <= disk_readonly;
	end
end

wire       mode; // read/write
wire [1:0] stp;
wire       mtr;
wire       act;
wire       soe;
wire [1:0] freq;
wire       wps_n = ~readonly ^ ch_state;
wire       tr00_sense_n;

c1541_logic c1541_logic
(
	.clk32(clk_c1541),
	.reset(reset),

	// serial bus
	.sb_clk_in(iec_clk_i),
	.sb_data_in(iec_data_i),
	.sb_atn_in(iec_atn_i),
	.sb_clk_out(iec_clk_o),
	.sb_data_out(iec_data_o),

	.c1541rom_clk(clk_sys),
	.c1541rom_addr(rom_addr),
	.c1541rom_data(rom_data),
	.c1541rom_wr(rom_wr),
	.c1541stdrom_wr(stdrom_wr),
	.c1541std(rom_std),

	// drive-side interface
	.ds(drive_num),
	.din(gcr_do),
	.dout(gcr_di),
	.mode(mode),
	.stp(stp),
	.mtr(mtr),
	.soe(soe),
	.freq(freq),
	.sync_n(sync_n),
	.byte_n(byte_n),
	.wps_n(wps_n),
	.tr00_sense_n(tr00_sense_n),
	.act(act)
);

wire       buff_dout;
wire       buff_din;
wire       buff_we;
wire [7:0] gcr_do;
wire [7:0] gcr_di;
wire       sync_n;
wire       byte_n;

c1541_gcr c1541_gcr
(
	.clk32(clk_c1541),

	.dout(gcr_do),
	.din(gcr_di),
	.mode(mode),
	.freq(freq),
	.soe(soe),
	.wps_n(wps_n),
	.sync_n(sync_n),
	.byte_n(byte_n),

	.ram_do(buff_dout),
	.ram_di(buff_din),
	.ram_we(buff_we)
);

c1541_track c1541_track
(
	.sd_clk(clk_sys),
	.sd_lba(sd_lba),
	.sd_rd(sd_rd),
	.sd_wr(sd_wr),
	.sd_ack(sd_ack),

	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(sd_buff_din),
	.sd_buff_wr(sd_buff_wr),

	.buff_dout(buff_dout),
	.buff_din(buff_din),
	.buff_we(buff_we),

	.disk_change(disk_change),
	.stp(stp),
	.mtr(mtr),
	.tr00_sense_n(tr00_sense_n),

	.clk(clk_c1541),
	.reset(reset),
	.busy(sd_busy)
);
endmodule
