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

module c1541_sd #(parameter PARPORT=0,DUALROM=1)
(
	//clk ports
	input         clk,
	input         ce,

	input         pause,

	input         img_mounted,
	input         img_readonly,
	input  [31:0] img_size,

	input   [1:0] drive_num,
	output        led,

	input         iec_reset_i,
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

	//clk_sys ports
	input         clk_sys,

	output [31:0] sd_lba,
	output  [5:0] sd_sz,
	output        sd_rd,
	output        sd_wr,
	input         sd_ack,
	input  [12:0] sd_buff_addr,
	input   [7:0] sd_buff_dout,
	output  [7:0] sd_buff_din,
	input         sd_buff_wr,

	input  [14:0] rom_addr,
	input   [7:0] rom_data,
	input         rom_wr,
	input         rom_std
);

assign led = act | sd_busy;

wire iec_atn, iec_data, iec_clk, reset_n;
c1541_sync atn_sync(clk, iec_atn_i,   iec_atn);
c1541_sync dat_sync(clk, iec_data_i,  iec_data);
c1541_sync clk_sync(clk, iec_clk_i,   iec_clk);
c1541_sync rst_sync(clk, iec_reset_i, reset_n);

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

c1541_logic #(PARPORT,DUALROM) c1541_logic
(
	.clk(clk),
	.ce(ce),
	.reset(~reset_n),
	.pause(pause),

	// serial bus
	.iec_clk_in(iec_clk),
	.iec_data_in(iec_data),
	.iec_atn_in(iec_atn),
	.iec_clk_out(iec_clk_o),
	.iec_data_out(iec_data_o),

	.rom_clk(clk_sys),
	.rom_addr(rom_addr),
	.rom_data(rom_data),
	.rom_wr(rom_wr),
	.rom_std(rom_std),

	// parallel bus
	.par_data_in(par_data_i),
	.par_stb_in(par_stb_i),
	.par_data_out(par_data_o),
	.par_stb_out(par_stb_o),

	// drive-side interface
	.ds(drive_num),
	.din(gcr_do),
	.dout(gcr_di),
	.mode(mode),
	.stp(stp),
	.mtr(mtr),
	.freq(freq),
	.sync_n(sync_n),
	.byte_n(byte_n),
	.wps_n(~readonly ^ ch_timeout[22]),
	.tr00_sense_n(|track),
	.act(act)
);

wire        we;
wire  [7:0] gcr_do;
wire  [7:0] gcr_di;
wire        sync_n;
wire        byte_n;

wire sd_busy;
c1541_sync busy_sync(clk, busy, sd_busy);

c1541_gcr c1541_gcr
(
	.clk(clk),
	.ce(ce),
	
	.dout(gcr_do),
	.din(gcr_di),
	.mode(mode),
	.mtr(mtr),
	.freq(freq),
	.sync_n(sync_n),
	.byte_n(byte_n),

	.track(track),
	.busy(sd_busy | ~disk_present),
	.we(we),

	.sd_clk(clk_sys),
	.sd_lba(sd_lba),
	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(sd_buff_din),
	.sd_buff_wr(sd_ack & sd_buff_wr)
);

wire busy;

c1541_track c1541_track
(
	.clk(clk_sys),
	.sd_lba(sd_lba),
	.sd_sz(sd_sz),
	.sd_rd(sd_rd),
	.sd_wr(sd_wr),
	.sd_ack(sd_ack),

	.save_track(save_track),
	.change(img_mounted),
	.track(track),
	.reset(~reset_n),
	.busy(busy)
);

reg [5:0] track;
reg       save_track = 0;
always @(posedge clk) begin
	reg       track_modified;
	reg [6:0] track_num;
	reg [1:0] move, stp_old;

	track <= track_num[6:1];

	stp_old <= stp;
	move <= stp - stp_old;

	if (we)          track_modified <= 1;
	if (img_mounted) track_modified <= 0;

	if (~reset_n) begin
		track_num <= 36;
		track_modified <= 0;
	end else begin
		if (mtr & move[0]) begin
			if (~move[1] && track_num < 80) track_num <= track_num + 1'b1;
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

// -------------------------------------------------------------------------------

module c1541_sync #(parameter WIDTH = 1) 
(
	input                  clk,
	input      [WIDTH-1:0] in,
	output reg [WIDTH-1:0] out
);

reg [WIDTH-1:0] s1,s2;
always @(posedge clk) begin
	s1 <= in;
	s2 <= s1;
	if(s1 == s2) out <= s2;
end

endmodule

// -------------------------------------------------------------------------------

module c1541mem #(parameter DATAWIDTH, ADDRWIDTH, INITFILE=" ")
(
	input	                     clock_a,
	input	     [ADDRWIDTH-1:0] address_a,
	input	     [DATAWIDTH-1:0] data_a,
	input	                     wren_a,
	output reg [DATAWIDTH-1:0] q_a,

	input	                     clock_b,
	input	     [ADDRWIDTH-1:0] address_b,
	input	     [DATAWIDTH-1:0] data_b,
	input	                     wren_b,
	output reg [DATAWIDTH-1:0] q_b
);

(* ram_init_file = INITFILE *) reg [DATAWIDTH-1:0] ram[0:(1<<ADDRWIDTH)-1];

always @(posedge clock_a) begin
	if(wren_a) begin
		ram[address_a] <= data_a;
		q_a <= data_a;
	end else begin
		q_a <= ram[address_a];
	end
end

always @(posedge clock_b) begin
	if(wren_b) begin
		ram[address_b] <= data_b;
		q_b <= data_b;
	end else begin
		q_b <= ram[address_b];
	end
end

endmodule
