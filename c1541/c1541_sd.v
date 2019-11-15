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
	.freq(),
	.sync_n(sync_n),
	.byte_n(byte_n),
	.wps_n(~readonly ^ ch_state),
	.tr00_sense_n(|track),
	.act(act)
);

wire [7:0] buff_dout;
wire [7:0] buff_din;
wire       buff_we;
wire [7:0] gcr_do;
wire [7:0] gcr_di;
wire       sync_n;
wire       byte_n;
wire [4:0] sector;
wire [7:0] byte_addr;

c1541_gcr c1541_gcr
(
	.clk32(clk_c1541),

	.dout(gcr_do),
	.din(gcr_di),
	.mode(mode),
	.mtr(mtr),
	.sync_n(sync_n),
	.byte_n(byte_n),

	.track(track),
	.sector(sector),

	.byte_addr(byte_addr),
	.ram_do(buff_dout),
	.ram_di(buff_din),
	.ram_we(buff_we),

	.ram_ready(~sd_busy)
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

	.buff_addr(byte_addr),
	.buff_dout(buff_dout),
	.buff_din(buff_din),
	.buff_we(buff_we),

	.save_track(save_track),
	.change(disk_change),
	.track(track),
	.sector(sector),

	.clk(clk_c1541),
	.reset(reset),
	.busy(sd_busy)
);

reg [5:0] track;
reg       save_track;
always @(posedge clk_c1541) begin
	reg       track_modified;
	reg [6:0] track_num;
	reg [1:0] stp_r;
	reg       act_r;

	stp_r <= stp;
	act_r <= act;
	save_track <= 0;
	track <= track_num[6:1];

	if (buff_we) track_modified <= 1;
	if (disk_change) track_modified <= 0;

	if (reset) begin
		track_num <= 36;
		track_modified <= 0;
	end else begin
		if (mtr) begin
			if ( (stp_r == 0 & stp == 2)
				| (stp_r == 2 & stp == 1)
				| (stp_r == 1 & stp == 3)
				| (stp_r == 3 & stp == 0)) begin
				if (track_num < 80) track_num <= track_num + 1'b1;
				save_track <= track_modified;
				track_modified <= 0;
			end

			if ( (stp_r == 0 & stp == 3)
				| (stp_r == 2 & stp == 0)
				| (stp_r == 1 & stp == 2)
				| (stp_r == 3 & stp == 1)) begin
				if (track_num > 1) track_num <= track_num - 1'b1;
				save_track <= track_modified;
				track_modified <= 0;
			end
		end

		if (act_r & ~act) begin		// stopping activity
			save_track <= track_modified;
			track_modified <= 0;
		end
	end
end

endmodule
