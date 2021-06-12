//-------------------------------------------------------------------------------
//
// C1541 multi-drive implementation with shared ROM
// (C) 2021 Alexey Melnikov
//
// Input clock/ce 16MHz
//
//-------------------------------------------------------------------------------


module c1581_multi #(parameter PARPORT=1,DUALROM=1,DRIVES=2)
(
	//clk ports
	input         clk,
	input   [N:0] reset,
	input         ce,

	input         pause,

	input   [N:0] img_mounted,
	input         img_readonly,
	input  [31:0] img_size,

	output  [N:0] act_led,
	output  [N:0] pwr_led,

	input         iec_atn_i,
	input         iec_data_i,
	input         iec_clk_i,
	input         iec_fclk_i,
	output        iec_data_o,
	output        iec_clk_o,
	output        iec_fclk_o,

	// parallel bus
	input   [7:0] par_data_i,
	input         par_stb_i,
	output  [7:0] par_data_o,
	output        par_stb_o,

	//clk_sys ports
	input         clk_sys,

	output [31:0] sd_lba[NDR],
	output  [N:0] sd_rd,
	output  [N:0] sd_wr,
	input   [N:0] sd_ack,
	input   [8:0] sd_buff_addr,
	input   [7:0] sd_buff_dout,
	output  [7:0] sd_buff_din[NDR],
	input         sd_buff_wr,

	input  [14:0] rom_addr,
	input   [7:0] rom_data,
	input         rom_wr,
	input         rom_std
);

localparam NDR = (DRIVES < 1) ? 1 : (DRIVES > 4) ? 4 : DRIVES;
localparam N   = NDR - 1;

wire iec_atn, iec_data, iec_clk, iec_fclk;
iecdrv_sync atn_sync(clk,  iec_atn_i,  iec_atn);
iecdrv_sync dat_sync(clk,  iec_data_i, iec_data);
iecdrv_sync clk_sync(clk,  iec_clk_i,  iec_clk);
iecdrv_sync fclk_sync(clk, iec_fclk_i, iec_fclk);

wire [N:0] reset_drv;
iecdrv_sync #(NDR) rst_sync(clk, reset, reset_drv);

wire stdrom = (DUALROM || PARPORT) ? rom_std : 1'b1;

reg ph2_r;
reg ph2_f;
reg wd_ce;
always @(posedge clk) begin
	reg [2:0] div;
	reg       ena, ena1;

	ena1 <= ~pause;
	if(div[1:0]) ena <= ena1;

	ph2_r <= 0;
	ph2_f <= 0;
	wd_ce  <= 0;
	if(ce) begin
		div <= div + 1'd1;
		ph2_r <= ena && !div[2] && !div[1:0];
		ph2_f <= ena &&  div[2] && !div[1:0];
		wd_ce  <= ena && !div[0];
	end
end

wire [7:0] rom_do;
generate
	if(PARPORT || DUALROM) begin
		iecdrv_mem #(8,15,"rtl/iec_drive/c1581_rom.mif") rom
		(
			.clock_a(clk_sys),
			.address_a(rom_addr),
			.data_a(rom_data),
			.wren_a(rom_wr),

			.clock_b(clk),
			.address_b(mem_a),
			.q_b(rom_do)
		);
	end
	else begin
		assign rom_do = romstd_do;
	end
endgenerate

wire [7:0] romstd_do;
iecdrv_mem #(8,15,"rtl/iec_drive/c1581_rom.mif") romstd
(
	.clock_a(clk_sys),
	.address_a(rom_addr),
	.data_a(rom_data),
	.wren_a((DUALROM || PARPORT) ? 1'b0 : rom_wr),

	.clock_b(clk),
	.address_b(mem_a),
	.q_b(romstd_do)
);

reg  [14:0] mem_a;
wire [14:0] drv_addr[NDR];
reg   [7:0] drv_data[4];
always @(posedge clk) begin
	reg [2:0] state;
	reg [14:0] mem_d;
	
	if(~&state) state <= state + 1'd1;
	if(ph2_f)   state <= 0;

	case(state)
		0,1,2,3: mem_a <= drv_addr[state[1:0]];
	endcase
	
	case(state)
		3,4,5,6: drv_data[state[1:0] - 2'd3] <= stdrom ? romstd_do : rom_do;
	endcase
end

wire [N:0] iec_data_d, iec_clk_d, iec_fclk_d;
assign     iec_clk_o  = &{iec_clk_d  | reset_drv};
assign     iec_fclk_o = &{iec_fclk_d | reset_drv};
assign     iec_data_o = &{iec_data_d | reset_drv};

wire [7:0] par_data_d[NDR];
wire [N:0] par_stb_d;
assign     par_stb_o = &{par_stb_d | reset_drv};
always_comb begin
	par_data_o = 8'hFF;
	for(int i=0; i<NDR; i=i+1) if(~reset_drv[i]) par_data_o = par_data_o & par_data_d[i];
end

wire [N:0] act_led_drv, pwr_led_drv;
assign     act_led = act_led_drv & ~reset_drv;
assign     pwr_led = pwr_led_drv & ~reset_drv;

generate
	genvar i;
	for(i=0; i<NDR; i=i+1) begin :drives
		c1581_drv c1581_drv
		(
			.clk(clk),
			.reset(reset_drv[i]),

			.ce(ce),
			.wd_ce(wd_ce),
			.ph2_r(ph2_r),
			.ph2_f(ph2_f),

			.img_mounted(img_mounted[i]),
			.img_readonly(img_readonly),
			.img_size(img_size),

			.drive_num(i),
			.act_led(act_led_drv[i]),
			.pwr_led(pwr_led_drv[i]),

			.iec_atn_i(iec_atn),
			.iec_data_i(iec_data & iec_data_o),
			.iec_clk_i(iec_clk & iec_clk_o),
			.iec_fclk_i(iec_fclk & iec_fclk_o),
			.iec_data_o(iec_data_d[i]),
			.iec_clk_o(iec_clk_d[i]),
			.iec_fclk_o(iec_fclk_d[i]),

			.par_data_i(par_data_i),
			.par_stb_i(par_stb_i),
			.par_data_o(par_data_d[i]),
			.par_stb_o(par_stb_d[i]),

			.rom_addr(drv_addr[i]),
			.rom_data(drv_data[i]),

			.clk_sys(clk_sys),

			.sd_lba(sd_lba[i]),
			.sd_rd(sd_rd[i]),
			.sd_wr(sd_wr[i]),
			.sd_ack(sd_ack[i]),
			.sd_buff_addr(sd_buff_addr),
			.sd_buff_dout(sd_buff_dout),
			.sd_buff_din(sd_buff_din[i]),
			.sd_buff_wr(sd_buff_wr)
		);
	end
endgenerate

endmodule
