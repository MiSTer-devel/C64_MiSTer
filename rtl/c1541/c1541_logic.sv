//-------------------------------------------------------------------------------
//
// Reworked and adapted to MiSTer by Sorgelig@MiSTer (07.09.2018)
//
//-------------------------------------------------------------------------------

//
// Model 1541B
//
module c1541_logic #(parameter PARPORT, DUALROM)
(
	input        clk,
	input        ce,
	input        reset,

	input        pause,

	// serial bus
	input        iec_clk_in,
	input        iec_data_in,
	input        iec_atn_in,
	output       iec_clk_out,
	output       iec_data_out,

	input        c1541rom_clk,
	input [14:0] c1541rom_addr,
	input  [7:0] c1541rom_data,
	input        c1541rom_wr,
	input        c1541std,

	// parallel bus
	input  [7:0] par_data_in,
	input        par_stb_in,
	output [7:0] par_data_out,
	output       par_stb_out,
	
	// drive-side interface
	input  [1:0] ds,			// device select
	input  [7:0] din,			// disk read data
	output [7:0] dout,		// disk write data
	output       mode,		// read/write
	output [1:0] stp,			// stepper motor control
	output       mtr,			// stepper motor on/off
	output [1:0] freq,		// motor frequency
	input        sync_n,		// reading SYNC bytes
	input        byte_n,		// byte ready
	input        wps_n,		// write-protect sense
	input        tr00_sense_n,	// track 0 sense (unused?)
	output       act			// activity LED
);

reg p2_h_r;
reg p2_h_f;
always @(posedge clk) begin
	reg [3:0] div;
	reg       ena, ena1;

	ena1 <= ~pause;
	if(div[2:0]) ena <= ena1;

	p2_h_r <= 0;
	p2_h_f <= 0;
	if(ce) begin
		div <= div + 1'd1;
		p2_h_r <= ena && !div[3] && !div[2:0];
		p2_h_f <= ena &&  div[3] && !div[2:0];
	end
end

wire stdrom = (DUALROM || PARPORT) ? c1541std : 1'b1;

//same decoder as on real HW
wire [3:0] ls42 = {cpu_a[15],cpu_a[12:10]};
wire ram_cs     = ls42 == 0 || ls42 == 1;
wire uc1_cs     = ls42 == 6;
wire uc3_cs     = ls42 == 7;
wire rom_cs     = cpu_a[15];

wire  [7:0] cpu_di =
	!cpu_rw    ? cpu_do :
	 ram_cs    ? ram_do :
	 uc1_cs    ? uc1_do :
	 uc3_cs    ? uc3_do :
	 rom_cs    ? (stdrom ? romstd_do : rom_do) :
	 8'hFF;

wire [23:0] cpu_a;
wire  [7:0] cpu_do;
wire        cpu_rw;
wire        cpu_irq_n = ~(uc1_irq | uc3_irq);
wire        cpu_so_n = byte_n | ~soe;

T65 cpu
(
	.mode(2'b00),
	.res_n(~reset),
	.enable(p2_h_f),
	.clk(clk),
	.rdy(1'b1),
	.abort_n(1'b1),
	.irq_n(cpu_irq_n),
	.nmi_n(1'b1),
	.so_n(cpu_so_n),
	.r_w_n(cpu_rw),
	.A(cpu_a),
	.DI(cpu_di),
	.DO(cpu_do)
);

initial begin
	rom_32k_i = 1;
	rom_16k_i = 1;
end

reg rom_32k_i;
reg rom_16k_i;
always @(posedge c1541rom_clk) if (c1541rom_wr & |c1541rom_data & ~&c1541rom_data) {rom_32k_i,rom_16k_i} <= c1541rom_addr[14:13];

reg [1:0] rom_sz;
always @(posedge clk) rom_sz <= {rom_32k_i,rom_32k_i|rom_16k_i}; // support for 8K/16K/32K ROM

reg [14:0] mem_a;
reg        ram_wr;
always @(posedge clk) begin
	ram_wr <= 0;
	if(p2_h_r) begin
		mem_a <= {cpu_a[14] & rom_sz[1], cpu_a[13] & (rom_sz[0] | stdrom), cpu_a[12:0]};
		ram_wr <= ~cpu_rw & ram_cs;
	end
end

wire [7:0] rom_do;
generate
	if(PARPORT) begin
		reg ram_ext_wr;
		always @(posedge clk) begin
			ram_ext_wr <= 0;
			if(p2_h_r) ram_ext_wr <= ~cpu_rw & rom_cs & ~cpu_a[14] & ~cpu_a[13] & rom_sz[1] & ~stdrom;
		end
	
		c1541mem #(8,15,"rtl/c1541/c1541_dolphin.mif") rom
		(
			.clock_a(c1541rom_clk),
			.address_a(c1541rom_addr),
			.data_a(c1541rom_data),
			.wren_a(c1541rom_wr),

			.clock_b(clk),
			.address_b(mem_a),
			.data_b(cpu_do),
			.wren_b(ram_ext_wr), // first 8KB is writable for Dolphin DOS
			.q_b(rom_do)
		);
	end
	else if(DUALROM) begin
		c1541mem #(8,14,"rtl/c1541/c1541_rom.mif") rom
		(
			.clock_a(c1541rom_clk),
			.address_a(c1541rom_addr[13:0]),
			.data_a(c1541rom_data),
			.wren_a(c1541rom_wr),

			.clock_b(clk),
			.address_b(mem_a[13:0]),
			.q_b(rom_do)
		);
	end
	else begin
		assign rom_do = 0;
	end
endgenerate

wire [7:0] romstd_do;
c1541mem #(8,14,"rtl/c1541/c1541_rom.mif") romstd
(
	.clock_a(c1541rom_clk),
	.address_a(c1541rom_addr[13:0]),
	.data_a(c1541rom_data),
	.wren_a((DUALROM || PARPORT) ? 1'b0 : c1541rom_wr),

	.clock_b(clk),
	.address_b(mem_a[13:0]),
	.q_b(romstd_do)
);

wire [7:0] ram_do;
c1541mem #(8,11) ram
(
	.clock_a(clk),
	.address_a(mem_a[10:0]),
	.data_a(cpu_do),
	.wren_a(ram_wr),

	.clock_b(clk),
	.address_b(mem_a[10:0]),
	.q_b(ram_do)
);

// UC1 (VIA6522) signals
wire [7:0] uc1_do;
wire       uc1_irq;
wire [7:0] uc1_pa_o;
wire [7:0] uc1_pa_oe;
wire       uc1_ca2_o;
wire       uc1_ca2_oe;
wire [7:0] uc1_pb_o;
wire [7:0] uc1_pb_oe;
wire       uc1_cb1_o;
wire       uc1_cb1_oe;
wire       uc1_cb2_o;
wire       uc1_cb2_oe;

assign     iec_data_out  = ~(uc1_pb_o[1] | ~uc1_pb_oe[1]) & ~((uc1_pb_o[4] | ~uc1_pb_oe[4]) ^ ~iec_atn_in);
assign     iec_clk_out   = ~(uc1_pb_o[3] | ~uc1_pb_oe[3]);

assign     par_stb_out  = uc1_ca2_o | ~uc1_ca2_oe;
assign     par_data_out = uc1_pa_o  | ~uc1_pa_oe;

c1541_via6522 uc1
(
	.clock(clk),
	.rising(p2_h_r),
	.falling(p2_h_f),
	.reset(reset),

	.addr(cpu_a[3:0]),
	.wen(~cpu_rw & uc1_cs),
	.ren(cpu_rw & uc1_cs),
	.data_in(cpu_do),
	.data_out(uc1_do),

	.port_a_o(uc1_pa_o),
	.port_a_t(uc1_pa_oe),
	.port_a_i((PARPORT ? par_data_in : {7'h7F,tr00_sense_n}) & (uc1_pa_o  | ~uc1_pa_oe)),

	.port_b_o(uc1_pb_o),
	.port_b_t(uc1_pb_oe),
	.port_b_i({~iec_atn_in, ds, 2'b11, ~(iec_clk_in & iec_clk_out), 1'b1, ~(iec_data_in & iec_data_out)} & (uc1_pb_o | ~uc1_pb_oe)),

	.ca1_i(~iec_atn_in),

	.ca2_o(uc1_ca2_o),
	.ca2_t(uc1_ca2_oe),
	.ca2_i(uc1_ca2_o | ~uc1_ca2_oe),

	.cb1_o(uc1_cb1_o),
	.cb1_t(uc1_cb1_oe),
	.cb1_i((PARPORT ? par_stb_in : 1'b1) & (uc1_cb1_o | ~uc1_cb1_oe)),

	.cb2_o(uc1_cb2_o),
	.cb2_t(uc1_cb2_oe),
	.cb2_i(uc1_cb2_o | ~uc1_cb2_oe),

	.irq(uc1_irq)
);


// UC3 (VIA6522) signals
wire [7:0] uc3_do;
wire       uc3_irq;
wire [7:0] uc3_pa_o;
wire [7:0] uc3_pa_oe;
wire       uc3_ca2_o;
wire       uc3_ca2_oe;
wire [7:0] uc3_pb_o;
wire [7:0] uc3_pb_oe;
wire       uc3_cb1_o;
wire       uc3_cb1_oe;
wire       uc3_cb2_o;
wire       uc3_cb2_oe;

wire       soe    = uc3_ca2_o | ~uc3_ca2_oe;
assign     dout   = uc3_pa_o  | ~uc3_pa_oe;
assign     mode   = uc3_cb2_o | ~uc3_cb2_oe;

assign     stp[1] = uc3_pb_o[0]   | ~uc3_pb_oe[0];
assign     stp[0] = uc3_pb_o[1]   | ~uc3_pb_oe[1];
assign     mtr    = uc3_pb_o[2]   | ~uc3_pb_oe[2];
assign     act    = uc3_pb_o[3]   | ~uc3_pb_oe[3];
assign     freq   = uc3_pb_o[6:5] | ~uc3_pb_oe[6:5];


c1541_via6522 uc3
(
	.clock(clk),
	.rising(p2_h_r),
	.falling(p2_h_f),
	.reset(reset),

	.addr(cpu_a[3:0]),
	.wen(~cpu_rw & uc3_cs),
	.ren(cpu_rw & uc3_cs),
	.data_in(cpu_do),
	.data_out(uc3_do),

	.port_a_o(uc3_pa_o),
	.port_a_t(uc3_pa_oe),
	.port_a_i(din & (uc3_pa_o | ~uc3_pa_oe)),

	.port_b_o(uc3_pb_o),
	.port_b_t(uc3_pb_oe),
	.port_b_i({sync_n, 2'b11, wps_n, 4'b1111} & (uc3_pb_o | ~uc3_pb_oe)),

	.ca1_i(cpu_so_n),

	.ca2_o(uc3_ca2_o),
	.ca2_t(uc3_ca2_oe),
	.ca2_i(uc3_ca2_o | ~uc3_ca2_oe),

	.cb1_o(uc3_cb1_o),
	.cb1_t(uc3_cb1_oe),
	.cb1_i(uc3_cb1_o | ~uc3_cb1_oe),

	.cb2_o(uc3_cb2_o),
	.cb2_t(uc3_cb2_oe),
	.cb2_i(uc3_cb2_o | ~uc3_cb2_oe),

	.irq(uc3_irq)
);

endmodule

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
