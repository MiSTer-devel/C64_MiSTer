//-------------------------------------------------------------------------------
//
// C1541 direct gcr module
// (C) 2021 Alexey Melnikov
//
//-------------------------------------------------------------------------------

module c1541_direct_gcr
(
	input        clk,
	input        ce,
	input        reset,
	
	output [7:0] dout,
	input  [7:0] din,
	input        mode,
	input        mtr,
	input  [1:0] freq,
	output       sync_n,
	output       byte_n,

	input        busy,
	output       we,
	
	input        sd_clk,
	input [13:0] sd_buff_addr,
	input  [7:0] sd_buff_dout,
	output [7:0] sd_buff_din,
	input        sd_buff_wr
);

assign sync_n      = ~mtr | busy | ~&shcur | ~mode;
assign byte_n      = ~mtr | busy | ~&bit_cnt | bt_n[1];
assign we          = buff_we;
assign sd_buff_din = (sd_buff_addr > track_len) ? 8'hFF : sd_buff_do;
assign dout        = shcur[7:0];

reg [13:0] track_len;
always @(posedge sd_clk) if(sd_buff_wr && !sd_buff_addr[13:1]) begin
	// size and possible flags
	if(sd_buff_addr[0] == 0) track_len[7:0]  <= sd_buff_dout;
	if(sd_buff_addr[0] == 1) track_len[13:8] <= sd_buff_dout[4:0];
end

wire [7:0] sd_buff_do;
iecdrv_bitmem #(13) buffer
(
	.clock_a(sd_clk),
	.address_a(sd_buff_addr[12:0]),
	.data_a(sd_buff_dout),
	.wren_a(sd_buff_wr & ~sd_buff_addr[13]),
	.q_a(sd_buff_do),

	.clock_b(clk),
	.address_b({buff_addr[15:3], ~buff_addr[2:0]}),
	.data_b(buff_di[~bit_cnt]),
	.wren_b(buff_we),
	.q_b(buff_do)
);

reg [15:0] buff_addr;
reg  [2:0] bit_cnt;
wire       buff_do;
reg  [7:0] buff_di;
reg        buff_we;

reg  [9:0] shreg;
wire [9:0] shcur = {shreg[8:0], buff_do};
reg  [1:0] bt_n;

always @(posedge clk) begin
	reg [5:0] bit_clk_cnt;

	buff_we <= 0;
	
	if(reset) begin
		buff_addr   <= 16;
		bit_clk_cnt <= 0;
		bit_cnt     <= 0;
		shreg       <= 0;
	end
	else if(busy | ~mtr) begin
		shreg       <= 0;
		bit_cnt     <= 0;
		bit_clk_cnt <= 0;
	end
	else if(ce) begin
		bt_n <= {bt_n[0],~&bit_cnt};

		if(buff_addr[15:3] > track_len) buff_addr <= 16;

		if (bit_clk_cnt == 'b110000) buff_we <= ~mode;

		bit_clk_cnt <= bit_clk_cnt + 1'b1;
		if (&bit_clk_cnt) begin
			buff_addr   <= buff_addr + 1'd1;
			if(buff_addr >= {track_len,3'b111}) buff_addr <= 16;

			bit_clk_cnt <= {2'b00,freq,2'b00};
			bit_cnt     <= bit_cnt + 1'b1;
			shreg       <= shcur;

			if(~sync_n) bit_cnt <= 0;
			if(bit_cnt == 7) buff_di <= din;
		end
	end
end

endmodule
