`timescale 1ns/1ps
// ============================================================================
// TAP time map - dual-port block RAM mapping counter position to TAP byte offset
//
// Port A: written by tap_scanner while the TAP file is loaded.
// Port B: read by the tape transport during FF/REW.
// ============================================================================

module tap_time_map #(
	parameter int AW = 13,           // address width: 2^AW entries
	parameter int DW = 25       // byte offset width, enough for the SDRAM TAP buffer
) (
	input        clk,

	// Write port (scanner)
	input  [AW-1:0] wr_addr,
	input  [DW-1:0] wr_data,
	input           wr_en,

	// Read port (transport)
	input  [AW-1:0] rd_addr,
	output reg [DW-1:0] rd_data
);

	reg [DW-1:0] ram [0:(1<<AW)-1];

	always @(posedge clk) begin
		if (wr_en) ram[wr_addr] <= wr_data;
		rd_data <= ram[rd_addr];
	end

endmodule
