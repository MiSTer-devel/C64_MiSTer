//-------------------------------------------------------------------------------
//
// C1541/C1581 selector
// (C) 2021 Alexey Melnikov
//
//-------------------------------------------------------------------------------

module iec_drive #(parameter PARPORT=1,DUALROM=1,DRIVES=2)
(
	//clk ports
	input         clk,
	input   [N:0] reset,
	input         ce,

	input         pause,

	input   [N:0] img_mounted,
	input         img_readonly,
	input  [31:0] img_size,
	
	// 00 - 1541 emulated GCR(D64)
	// 01 - 1541 real GCR mode (G64,D64)
	// 10 - 1581 (D81)
	input   [1:0] img_type,

	output  [N:0] led,
	output        disk_ready,

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

	output [31:0] sd_lba[NDR],
	output  [5:0] sd_blk_cnt[NDR],
	output  [N:0] sd_rd,
	output  [N:0] sd_wr,
	input   [N:0] sd_ack,
	input  [13:0] sd_buff_addr,
	input   [7:0] sd_buff_dout,
	output  [7:0] sd_buff_din[NDR],
	input         sd_buff_wr,

	input  [15:0] rom_addr,
	input   [7:0] rom_data,
	input         rom_wr,
	input         rom_std
);

localparam NDR = (DRIVES < 1) ? 1 : (DRIVES > 4) ? 4 : DRIVES;
localparam N   = NDR - 1;

reg [N:0] dtype[2];
always @(posedge clk_sys) for(int i=0; i<NDR; i=i+1) if(img_mounted[i] && img_size) {dtype[1][i],dtype[0][i]} <= img_type;

assign led          = c1581_led       | c1541_led;
assign iec_data_o   = c1581_iec_data  & c1541_iec_data;
assign iec_clk_o    = c1581_iec_clk   & c1541_iec_clk;
assign par_stb_o    = c1581_stb_o     & c1541_stb_o;
assign par_data_o   = c1581_par_o     & c1541_par_o;

always_comb for(int i=0; i<NDR; i=i+1) begin
	sd_buff_din[i] = (dtype[1][i] ? c1581_sd_buff_dout[i] : c1541_sd_buff_dout[i] );
	sd_lba[i]      = (dtype[1][i] ? c1581_sd_lba[i] << 1  : c1541_sd_lba[i]       );
	sd_rd[i]       = (dtype[1][i] ? c1581_sd_rd[i]        : c1541_sd_rd[i]        );
	sd_wr[i]       = (dtype[1][i] ? c1581_sd_wr[i]        : c1541_sd_wr[i]        );
	sd_blk_cnt[i]  = (dtype[1][i] ? 6'd1                  : c1541_sd_blk_cnt[i]   );
end

wire        c1541_iec_data, c1541_iec_clk, c1541_stb_o;
wire  [7:0] c1541_par_o;
wire  [N:0] c1541_led;
wire  [7:0] c1541_sd_buff_dout[NDR];
wire [31:0] c1541_sd_lba[NDR];
wire  [N:0] c1541_sd_rd, c1541_sd_wr;
wire  [5:0] c1541_sd_blk_cnt[NDR];

c1541_multi #(.PARPORT(PARPORT), .DUALROM(DUALROM), .DRIVES(DRIVES)) c1541
(
	.clk(clk),
	.reset(reset | dtype[1]),
	.ce(ce),

	.gcr_mode(dtype[0]),

	.iec_atn_i (iec_atn_i),
	.iec_data_i(iec_data_i & c1581_iec_data),
	.iec_clk_i (iec_clk_i  & c1581_iec_clk),
	.iec_data_o(c1541_iec_data),
	.iec_clk_o (c1541_iec_clk),

	.led(c1541_led),
	.disk_ready(disk_ready),

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

	.img_mounted(img_mounted),
	.img_size(img_size),
	.img_readonly(img_readonly),

	.sd_lba(c1541_sd_lba),
	.sd_blk_cnt(c1541_sd_blk_cnt),
	.sd_rd(c1541_sd_rd),
	.sd_wr(c1541_sd_wr),
	.sd_ack(sd_ack),
	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(c1541_sd_buff_dout),
	.sd_buff_wr(sd_buff_wr)
);


wire        c1581_iec_data, c1581_iec_clk, c1581_stb_o;
wire  [7:0] c1581_par_o;
wire  [N:0] c1581_led;
wire  [7:0] c1581_sd_buff_dout[NDR];
wire [31:0] c1581_sd_lba[NDR];
wire  [N:0] c1581_sd_rd, c1581_sd_wr;

c1581_multi #(.PARPORT(PARPORT), .DUALROM(DUALROM), .DRIVES(DRIVES)) c1581
(
	.clk(clk),
	.reset(reset | ~dtype[1]),
	.ce(ce),

	.iec_atn_i (iec_atn_i),
	.iec_data_i(iec_data_i & c1541_iec_data),
	.iec_clk_i (iec_clk_i  & c1541_iec_clk),
	.iec_fclk_i (1),
	.iec_data_o(c1581_iec_data),
	.iec_clk_o (c1581_iec_clk),

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
	.sd_buff_addr(sd_buff_addr[8:0]),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(c1581_sd_buff_dout),
	.sd_buff_wr(sd_buff_wr)
);

endmodule
