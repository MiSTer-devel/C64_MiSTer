
module iecdrv_sync #(parameter WIDTH = 1) 
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

module iecdrv_mem #(parameter DATAWIDTH, ADDRWIDTH, INITFILE=" ")
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

(* ram_init_file = INITFILE *) reg [DATAWIDTH-1:0] ram[1<<ADDRWIDTH];

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

module iecdrv_bitmem #(parameter ADDRWIDTH)
(
	input	                     clock_a,
	input	     [ADDRWIDTH-1:0] address_a,
	input	               [7:0] data_a,
	input	                     wren_a,
	output reg           [7:0] q_a,

	input	                     clock_b,
	input	     [ADDRWIDTH+2:0] address_b,
	input	                     data_b,
	input	                     wren_b,
	output reg                 q_b
);
    
reg [7:0] ram[1<<ADDRWIDTH];

reg                 wren_a_d;
reg [ADDRWIDTH-1:0] address_a_d;
reg           [7:0] data_a_d;
always @(posedge clock_a) begin
	wren_a_d    <= wren_a;
	address_a_d <= address_a;
	data_a_d    <= data_a;
end

always @(posedge clock_a) begin
	if(wren_a_d) begin
		ram[address_a_d] <= data_a_d;
		q_a <= data_a_d;
	end else begin
		q_a <= ram[address_a_d];
	end
end

reg                 wren_b_d;
reg [ADDRWIDTH+2:0] address_b_d;
reg                 data_b_d;
always @(posedge clock_b) begin
	wren_b_d    <= wren_b;
	address_b_d <= address_b;
	data_b_d    <= data_b;
end

always @(posedge clock_b) begin
	if(wren_b_d) begin
		ram[address_b_d[ADDRWIDTH+2:3]][address_b_d[2:0]] <= data_b_d;
		q_b <= data_b_d;
	end else begin
		q_b <= ram[address_b_d[ADDRWIDTH+2:3]][address_b_d[2:0]];
	end
end

endmodule

module iecdrv_bitmem64 #(parameter ADDRWIDTH)
(
	input	                     clock_a,
	input	     [ADDRWIDTH-1:0] address_a,
	input	              [63:0] data_a,
	input	                     wren_a,
	output wire          [63:0] q_a,

	input	                     clock_b,
	input	     [ADDRWIDTH+5:0] address_b,
	input	                     data_b,
	input	                     wren_b,
	output wire                 q_b
);

wire [7:0] q_a_bytes[8];
wire q_b_bits[8];

genvar i;
generate
	for(i=0; i<8; i=i+1) begin : rams
		iecdrv_bitmem #(ADDRWIDTH) bitmem (
			.clock_a(clock_a),
			.address_a(address_a),
			.data_a(data_a[i*8 +: 8]),
			.wren_a(wren_a),
			.q_a(q_a_bytes[i]),

			.clock_b(clock_b),
			.address_b({address_b[ADDRWIDTH+5:6], address_b[2:0]}),
			.data_b(data_b),
			.wren_b(wren_b & (address_b[5:3] == i[2:0])),
			.q_b(q_b_bits[i])
		);
	end
endgenerate

assign q_a = {q_a_bytes[7], q_a_bytes[6], q_a_bytes[5], q_a_bytes[4],
              q_a_bytes[3], q_a_bytes[2], q_a_bytes[1], q_a_bytes[0]};

reg [2:0] b_sel_d, b_sel_d2;
always @(posedge clock_b) begin
	b_sel_d <= address_b[5:3];
	b_sel_d2 <= b_sel_d;
end

assign q_b = q_b_bits[b_sel_d2];

endmodule

// -------------------------------------------------------------------------------

module iecdrv_bitmemSP #(parameter ADDRWIDTH)
(
	input	                     clock_a,
	input	     [ADDRWIDTH-1:0] address_a,
	input	               [7:0] data_a,
	input	                     wren_a,
	output reg           [7:0] q_a
);

reg [7:0] ram[1<<ADDRWIDTH];

reg                 wren_a_d;
reg [ADDRWIDTH-1:0] address_a_d;
reg           [7:0] data_a_d;
always @(posedge clock_a) begin
	wren_a_d    <= wren_a;
	address_a_d <= address_a;
	data_a_d    <= data_a;
end

always @(posedge clock_a) begin
	if(wren_a_d) begin
		ram[address_a_d] <= data_a_d;
		q_a <= data_a_d;
	end else begin
		q_a <= ram[address_a_d];
	end
end

endmodule

module iecdrv_bitmem64SP #(parameter ADDRWIDTH)
(
	input	                     clock_a,
	input	     [ADDRWIDTH-1:0] address_a,
	input	              [63:0] data_a,
	input	                     wren_a,
	output wire          [63:0] q_a
);

wire [7:0] q_a_bytes[8];

genvar i;
generate
	for(i=0; i<8; i=i+1) begin : rams
		iecdrv_bitmemSP #(ADDRWIDTH) bitmem (
			.clock_a(clock_a),
			.address_a(address_a),
			.data_a(data_a[i*8 +: 8]),
			.wren_a(wren_a),
			.q_a(q_a_bytes[i])
		);
	end
endgenerate

assign q_a = {q_a_bytes[7], q_a_bytes[6], q_a_bytes[5], q_a_bytes[4],
              q_a_bytes[3], q_a_bytes[2], q_a_bytes[1], q_a_bytes[0]};

endmodule
