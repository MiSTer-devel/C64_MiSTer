//-------------------------------------------------------------------------------
//
// Commodore 1581 implementation
// (C) 2021 Alexey Melnikov
//
// Input clock 16MHz
//
//-------------------------------------------------------------------------------

module c1581_sd #(parameter PARPORT=0,DUALROM=1)
(
	//clk ports
	input         clk,
	input         ce,

	input         pause,

	input   [1:0] drive_num,
	output        act_led,
	output        pwr_led,

	input         iec_reset_i,
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

	input         img_mounted,
	input  [31:0] img_size,
	input         img_readonly,

	output [31:0] sd_lba,
	output        sd_rd,
	output        sd_wr,
	input         sd_ack,
	input   [8:0] sd_buff_addr,
	input   [7:0] sd_buff_dout,
	output  [7:0] sd_buff_din,
	input         sd_buff_wr,

	input  [14:0] rom_addr,
	input   [7:0] rom_data,
	input         rom_wr,
	input         rom_std
);

reg wps_n = 0;
always @(posedge clk) begin
	reg prev_mounted;
	prev_mounted <= img_mounted;
	if (~prev_mounted & img_mounted) wps_n <= ~img_readonly;
end

wire iec_atn, iec_data, iec_clk, iec_reset;
c1581_sync atn_sync(clk, iec_atn_i,   iec_atn);
c1581_sync dat_sync(clk, iec_data_i,  iec_data);
c1581_sync clk_sync(clk, iec_clk_i,   iec_clk);
c1581_sync rst_sync(clk, iec_reset_i, iec_reset);

reg p2_h_r;
reg p2_h_f;
reg wd_ce;
always @(posedge clk) begin
	reg [2:0] div;
	reg       ena, ena1;

	ena1 <= ~pause;
	if(div[1:0]) ena <= ena1;

	p2_h_r <= 0;
	p2_h_f <= 0;
	wd_ce  <= 0;
	if(ce) begin
		div <= div + 1'd1;
		p2_h_r <= ena && !div[2] && !div[1:0];
		p2_h_f <= ena &&  div[2] && !div[1:0];
		wd_ce  <= ena && !div[0];
	end
end

wire stdrom = (DUALROM || PARPORT) ? rom_std : 1'b1;

//same decoder as on real HW
wire [2:0] ls193 = cpu_a[15:13];
wire ram_cs      = ls193 == 0;
wire via_cs      = ls193 == 1;
wire cia_cs      = ls193 == 2;
wire wd_cs       = ls193 == 3;
wire rom_cs      = cpu_a[15];

wire  [7:0] cpu_di =
	!cpu_rw ? cpu_do :
	 ram_cs ? ram_do :
	 via_cs ? via_do :
	 cia_cs ? cia_do :
	 wd_cs  ? wd_do  :
	 rom_cs ? rom_dout :
	 8'hFF;

wire [23:0] cpu_a;
wire  [7:0] cpu_do;
wire        cpu_rw;

T65 cpu
(
	.clk(clk),
	.enable(p2_h_r),
	.mode(2'b00),
	.res_n(~iec_reset),
	.irq_n(cia_irq_n & ~via_irq),
	.r_w_n(cpu_rw),
	.A(cpu_a),
	.DI(cpu_di),
	.DO(cpu_do)
);

wire [7:0] rom_do;
generate
	if(PARPORT || DUALROM) begin
		c1581mem #(8,15,"rtl/c1581/c1581_rom.mif") rom
		(
			.clock_a(clk_sys),
			.address_a(rom_addr),
			.data_a(rom_data),
			.wren_a(rom_wr),

			.clock_b(clk),
			.address_b(cpu_a[14:0]),
			.q_b(rom_do)
		);
	end
	else begin
		assign rom_do = 0;
	end
endgenerate

wire [7:0] romstd_do;
c1581mem #(8,15,"rtl/c1581/c1581_rom.mif") romstd
(
	.clock_a(clk_sys),
	.address_a(rom_addr),
	.data_a(rom_data),
	.wren_a((DUALROM || PARPORT) ? 1'b0 : rom_wr),

	.clock_b(clk),
	.address_b(cpu_a[14:0]),
	.q_b(romstd_do)
);

wire [7:0] rom_dout = stdrom ? romstd_do : rom_do;

wire [7:0] ram_do;
c1581mem #(8,13) ram
(
	.clock_a(clk),
	.address_a(cpu_a[12:0]),
	.data_a(cpu_do),
	.wren_a(p2_h_f & ~cpu_rw & ram_cs),

	.clock_b(clk),
	.address_b(cpu_a[12:0]),
	.q_b(ram_do)
);

wire [7:0] cia_do;
wire       cia_irq_n;

assign     act_led    =  pa_out[6];
assign     pwr_led    =  pa_out[5];
wire       motor_n    =  pa_out[2];
wire       side       =  pa_out[0];
wire [7:0] pa_in      = {disk_chng_n, 2'b11, drive_num, 1'b1, ~floppy_ready, 1'b1};

wire       fast_dir   =  pb_out[5];
assign     iec_clk_o  = ~pb_out[3];
assign     iec_data_o = ~pb_out[1] & ~(pb_out[4] & ~iec_atn) & (~fast_dir | sp_out);
assign     iec_fclk_o = ~fast_dir | cnt_out;
wire [7:0] pb_in      = {~iec_atn, wps_n, 3'b111, ~(iec_clk & iec_clk_o), 1'b1, ~(iec_data & iec_data_o)};

wire [7:0] pa_out;
wire [7:0] pb_out;

wire       sp_out;
wire       cnt_out;

c1581_mos8520 cia
(
	.clk(clk),
	.phi2_p(p2_h_r),
	.phi2_n(p2_h_f),
	.res_n(~iec_reset),
	.cs_n(~cia_cs),
	.rw(cpu_rw),

	.rs(cpu_a[3:0]),
	.db_in(cpu_do),
	.db_out(cia_do),

	.pa_in(pa_in & pa_out),
	.pa_out(pa_out),
	.pb_in(pb_in & pb_out),
	.pb_out(pb_out),

	.flag_n(iec_atn),

	.tod(p2_h_f),

	.sp_in(fast_dir | iec_data),
	.sp_out(sp_out),

	.cnt_in(fast_dir | iec_fclk_i),
	.cnt_out(cnt_out),

	.irq_n(cia_irq_n)
);


wire [7:0] via_do;
wire       via_irq;
wire [7:0] via_pa_o;
wire [7:0] via_pa_oe;
wire       via_ca2_o;
wire       via_ca2_oe;
wire [7:0] via_pb_o;
wire [7:0] via_pb_oe;
wire       via_cb1_o;
wire       via_cb1_oe;
wire       via_cb2_o;
wire       via_cb2_oe;

assign     par_stb_o  = via_ca2_o | ~via_ca2_oe;
assign     par_data_o = via_pa_o  | ~via_pa_oe;

c1581_via6522 via
(
	.clock(clk),
	.rising(p2_h_f),
	.falling(p2_h_r),
	.reset(iec_reset),

	.addr(cpu_a[3:0]),
	.wen(~cpu_rw & via_cs),
	.ren(cpu_rw & via_cs),
	.data_in(cpu_do),
	.data_out(via_do),

	.port_a_o(via_pa_o),
	.port_a_t(via_pa_oe),
	.port_a_i(par_data_i & (via_pa_o  | ~via_pa_oe)),

	.port_b_o(via_pb_o),
	.port_b_t(via_pb_oe),
	.port_b_i(via_pb_o | ~via_pb_oe),

	.ca1_i(1'b1),

	.ca2_o(via_ca2_o),
	.ca2_t(via_ca2_oe),
	.ca2_i(via_ca2_o | ~via_ca2_oe),

	.cb1_o(via_cb1_o),
	.cb1_t(via_cb1_oe),
	.cb1_i(par_stb_i & (via_cb1_o | ~via_cb1_oe)),

	.cb2_o(via_cb2_o),
	.cb2_t(via_cb2_oe),
	.cb2_i(via_cb2_o | ~via_cb2_oe),

	.irq(via_irq)
);


reg disk_chng_n;
always @(posedge clk) begin
	if(img_mounted | iec_reset) disk_chng_n <=0;
	if(floppy_step) disk_chng_n <=1;
end

wire       floppy_step;
wire [7:0] wd_do;

wire floppy_ready;

fdc1772 #(.SECTOR_SIZE_CODE(2), .SECTOR_BASE(1), .EXT_MOTOR(1), .FD_NUM(1)) fdc
(
	.clkcpu(clk),
	.clk8m_en(wd_ce),

	.floppy_drive(1'b0),
	.floppy_side(~side), 
	.floppy_reset(~iec_reset),
	.floppy_step(floppy_step),
	.floppy_motor(~motor_n),
	.floppy_ready(floppy_ready),

	.cpu_addr(cpu_a[1:0]),
	.cpu_sel(wd_cs),
	.cpu_rw(cpu_rw | ~p2_h_f),
	.cpu_din(cpu_do),
	.cpu_dout(wd_do),

	.img_wp(~wps_n),

	.img_mounted(img_mounted),
	.img_size(img_size),
	.sd_lba(sd_lba),
	.sd_rd(sd_rd),
	.sd_wr(sd_wr),
	.sd_ack(sd_ack),
	.sd_buff_addr(sd_buff_addr),
	.sd_dout(sd_buff_dout),
	.sd_din(sd_buff_din),
	.sd_dout_strobe(sd_buff_wr)
);

endmodule

module c1581mem #(parameter DATAWIDTH, ADDRWIDTH, INITFILE=" ")
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

reg                 wren_a_d;
reg [ADDRWIDTH-1:0] address_a_d;
always @(posedge clock_a) begin
	wren_a_d    <= wren_a;
	address_a_d <= address_a;
end

always @(posedge clock_a) begin
	if(wren_a_d) begin
		ram[address_a_d] <= data_a;
		q_a <= data_a;
	end else begin
		q_a <= ram[address_a_d];
	end
end

reg                 wren_b_d;
reg [ADDRWIDTH-1:0] address_b_d;
always @(posedge clock_b) begin
	wren_b_d    <= wren_b;
	address_b_d <= address_b;
end

always @(posedge clock_b) begin
	if(wren_b_d) begin
		ram[address_b_d] <= data_b;
		q_b <= data_b;
	end else begin
		q_b <= ram[address_b_d];
	end
end

endmodule

module c1581_sync
(
	input      clk,
	input      in,
	output reg out
);

reg s1,s2;
always @(posedge clk) begin
	s1 <= in;
	s2 <= s1;
	if(s1 == s2) out <= s2;
end

endmodule
