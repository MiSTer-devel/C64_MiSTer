`timescale 1ns/1ps
// ============================================================================
// TAP time map - dual-port block RAM per mappa contatore -> byte offset
//
// Porta A: scrittura dal tap_scanner durante il caricamento.
// Porta B: lettura dal top-level durante FF/REW.
// ============================================================================

module tap_time_map #(
	parameter int AW = 13,      // indirizzo: 2^AW entry
	parameter int DW = 25       // 25 bit per offset byte (max 4 MB in SDRAM)
) (
	input        clk,

	// Porta scrittura (scanner)
	input  [AW-1:0] wr_addr,
	input  [DW-1:0] wr_data,
	input           wr_en,

	// Porta lettura (top-level)
	input  [AW-1:0] rd_addr,
	output reg [DW-1:0] rd_data
);

	reg [DW-1:0] ram [0:(1<<AW)-1];

	always @(posedge clk) begin
		if (wr_en) ram[wr_addr] <= wr_data;
		rd_data <= ram[rd_addr];
	end

endmodule
