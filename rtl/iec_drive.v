//-------------------------------------------------------------------------------
//
// C1541/C1581 selector
// (C) 2021 Alexey Melnikov
//
//-------------------------------------------------------------------------------

module iec_drive
(
	input         clk,
	input         ce,

	input         pause,

	input   [1:0] drive_num,
	output        led,

	input         iec_reset_i,
	input         iec_atn_i,
	input         iec_data_i,
	input         iec_clk_i,
	output        iec_data_o,
	output        iec_clk_o,

	input   [7:0] par_data_i,
	input         par_stb_i,
	output  [7:0] par_data_o,
	output        par_stb_o,

	input         clk_sys,

	input         img_mounted,
	input  [31:0] img_size,
	input         img_readonly,
	input         img_type,

	output [31:0] sd_lba,
	output        sd_rd,
	output        sd_wr,
	input         sd_ack,
	input   [8:0] sd_buff_addr,
	input   [7:0] sd_buff_dout,
	output  [7:0] sd_buff_din,
	input         sd_buff_wr,

	input  [15:0] rom_addr,
	input   [7:0] rom_data,
	input         rom_wr,
	input         rom_std
);

reg dtype;
always @(posedge clk_sys) if(img_mounted && img_size) dtype <= img_type;

assign led          = dtype ? c1581_led          : c1541_led          ;
assign iec_data_o   = dtype ? c1581_iec_data     : c1541_iec_data     ;
assign iec_clk_o    = dtype ? c1581_iec_clk      : c1541_iec_clk      ;
assign par_stb_o    = dtype ? c1581_stb_o        : c1541_stb_o        ;
assign par_data_o   = dtype ? c1581_par_o        : c1541_par_o        ;
assign sd_buff_din  = dtype ? c1581_sd_buff_dout : c1541_sd_buff_dout ;
assign sd_lba       = dtype ? c1581_sd_lba       : c1541_sd_lba       ;
assign sd_rd        = dtype ? c1581_sd_rd        : c1541_sd_rd        ;
assign sd_wr        = dtype ? c1581_sd_wr        : c1541_sd_wr        ;

wire        c1541_iec_data, c1541_iec_clk, c1541_led, c1541_stb_o;
wire  [7:0] c1541_par_o, c1541_sd_buff_dout;
wire [31:0] c1541_sd_lba;
wire        c1541_sd_rd, c1541_sd_wr;

c1541 #(1) c1541
(
	.clk(clk),
	.ce(ce),

	.iec_reset_i(iec_reset_i | dtype),

	.iec_atn_i (iec_atn_i),
	.iec_data_i(iec_data_i),
	.iec_clk_i (iec_clk_i),
	.iec_data_o(c1541_iec_data),
	.iec_clk_o(c1541_iec_clk),

	.drive_num(drive_num),
	.led(c1541_led),

	.par_data_i(par_data_i),
	.par_stb_i(par_stb_i),
	.par_data_o(c1541_par_o),
	.par_stb_o(c1541_stb_o),

	.clk_sys(clk_sys),
	.pause(pause),

	.rom_addr(rom_addr[14:0]),
	.rom_data(rom_data),
	.rom_wr(~rom_addr[15] & rom_wr),
	.rom_std(rom_std),

	.disk_change(img_mounted),
	.disk_readonly(img_readonly),

	.sd_lba(c1541_sd_lba),
	.sd_rd(c1541_sd_rd),
	.sd_wr(c1541_sd_wr),
	.sd_ack(sd_ack),
	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(c1541_sd_buff_dout),
	.sd_buff_wr(sd_buff_wr)
);


wire        c1581_iec_data, c1581_iec_clk, c1581_led, c1581_stb_o;
wire  [7:0] c1581_par_o, c1581_sd_buff_dout;
wire [31:0] c1581_sd_lba;
wire        c1581_sd_rd, c1581_sd_wr;

c1581 #(1) c1581
(
	.clk(clk),
	.ce(ce),

	.iec_reset_i(iec_reset_i | ~dtype),

	.iec_atn_i (iec_atn_i),
	.iec_data_i(iec_data_i),
	.iec_clk_i (iec_clk_i),
	.iec_data_o(c1581_iec_data),
	.iec_clk_o(c1581_iec_clk),

	.drive_num(drive_num),
	.act_led(c1581_led),

	.par_data_i(par_data_i),
	.par_stb_i(par_stb_i),
	.par_data_o(c1581_par_o),
	.par_stb_o(c1581_stb_o),

	.clk_sys(clk_sys),
	.pause(pause),

	.rom_addr(rom_addr[14:0]),
	.rom_data(rom_data),
	.rom_wr(rom_addr[15] & rom_wr),
	.rom_std(rom_std),

	.img_mounted(img_mounted),
	.img_size(img_size),
	.img_readonly(img_readonly),

	.sd_lba(c1581_sd_lba),
	.sd_rd(c1581_sd_rd),
	.sd_wr(c1581_sd_wr),
	.sd_ack(sd_ack),
	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(c1581_sd_buff_dout),
	.sd_buff_wr(sd_buff_wr)
);

endmodule
