module random_xor (
	input clock,
	input reset,
	input [31:0] seed,
	output reg [31:0] lfsr
);

always @(posedge clock) begin
	if (reset) begin
		// initialize with non-zero seed
		lfsr <= (seed != 0) ? seed : 32'h1234abcd;
	end else begin
		lfsr <=  ((lfsr ^ (lfsr << 13)) ^ ((lfsr ^ (lfsr << 13)) >> 17)) ^
		        (((lfsr ^ (lfsr << 13)) ^ ((lfsr ^ (lfsr << 13)) >> 17)) << 5);
		end
end

endmodule
