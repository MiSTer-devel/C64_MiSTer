//
// sdram.v
//
// sdram controller implementation for the MiST board
// http://code.google.com/p/mist-board/
// 
// Copyright (c) 2013 Till Harbaum <till@harbaum.org> 
// 
// This source file is free software: you can redistribute it and/or modify 
// it under the terms of the GNU General Public License as published 
// by the Free Software Foundation, either version 3 of the License, or 
// (at your option) any later version. 
// 
// This source file is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of 
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the 
// GNU General Public License for more details.
// 
// You should have received a copy of the GNU General Public License 
// along with this program.  If not, see <http://www.gnu.org/licenses/>. 
//

module sdram (

	// interface to the MT48LC16M16 chip
	output reg [12:0]	sd_addr,    // 13 bit multiplexed address bus
	inout  reg [15:0]	sd_data,
	output reg [ 1:0]	sd_ba,      // two banks
	output 				sd_cs,      // a single chip select
	output 				sd_we,      // write enable
	output 				sd_ras,     // row address select
	output 				sd_cas,     // columns address select
	output 				sd_clk,
	output 		[1:0]	sd_dqm,

	// cpu/chipset interface
	input 		 		init,			// init signal after FPGA config to initialize RAM
	input 		 		clk,			// sdram is accessed at up to 128MHz
	
	input      [24:0] addr,       // 25 bit byte address
	input      [ 7:0] din,
	output     [ 7:0]	dout,

	input 		 		refresh,    // refresh cycle
	input 		 		ce,         // cpu/chipset access
	input 		 		we          // cpu/chipset requests write
);

// no burst configured
localparam RASCAS_DELAY   = 3'd2;   // tRCD>=20ns -> 2 cycles@64MHz
localparam BURST_LENGTH   = 3'b000; // 000=none, 001=2, 010=4, 011=8
localparam ACCESS_TYPE    = 1'b0;   // 0=sequential, 1=interleaved
localparam CAS_LATENCY    = 3'd2;   // 2/3 allowed
localparam OP_MODE        = 2'b00;  // only 00 (standard operation) allowed
localparam NO_WRITE_BURST = 1'b1;   // 0= write burst enabled, 1=only single access write

localparam MODE = { 3'b000, NO_WRITE_BURST, OP_MODE, CAS_LATENCY, ACCESS_TYPE, BURST_LENGTH}; 

// ---------------------------------------------------------------------
// ------------------------ cycle state machine ------------------------
// ---------------------------------------------------------------------

localparam STATE_CMD_START = 3'd0;   // state in which a new command can be started
localparam STATE_CMD_CONT  = STATE_CMD_START  + RASCAS_DELAY; // command can be continued
localparam STATE_READ      = STATE_CMD_CONT + CAS_LATENCY + 1'd1;
localparam STATE_LAST      = 3'd7;   // last state in cycle

reg [2:0] q /* synthesis noprune */;
reg last_ce, last_refresh;
always @(posedge clk) begin
	last_ce <= ce;
	last_refresh <= refresh;

	// start a new cycle in rising edge of ce
	if(ce && !last_ce) q <= 3'd1;
	if(q || reset) q <= q + 3'd1;
end

// ---------------------------------------------------------------------
// --------------------------- startup/reset ---------------------------
// ---------------------------------------------------------------------

// wait 1ms (32 clkref cycles) after FPGA config is done before going
// into normal operation. Initialize the ram in the last 16 reset cycles (cycles 15-0)
initial reset = 5'h1f;

reg [4:0] reset;
always @(posedge clk) begin
	if(init)	reset <= 5'h1f;
	else if((q == STATE_LAST) && (reset != 0)) reset <= reset - 5'd1;
end

// ---------------------------------------------------------------------
// ------------------ generate ram control signals ---------------------
// ---------------------------------------------------------------------

// all possible commands
localparam CMD_NOP             = 3'b111;
localparam CMD_ACTIVE          = 3'b011;
localparam CMD_READ            = 3'b101;
localparam CMD_WRITE           = 3'b100;
localparam CMD_BURST_TERMINATE = 3'b110;
localparam CMD_PRECHARGE       = 3'b010;
localparam CMD_AUTO_REFRESH    = 3'b001;
localparam CMD_LOAD_MODE       = 3'b000;

reg [2:0] sd_cmd;   // current command sent to sd ram

// drive control signals according to current command
assign sd_cs  = 0;
assign sd_ras = sd_cmd[2];
assign sd_cas = sd_cmd[1];
assign sd_we  = sd_cmd[0];
assign sd_dqm = sd_addr[12:11];

reg bt;
reg [15:0] dout_r;

assign dout = bt ? dout_r[15:8] : dout_r[7:0];

always @(posedge clk) begin
	reg [8:0] caddr;
	reg [7:0] wrdata;
	reg       wr;

	sd_cmd  <= CMD_NOP;
	sd_data <= 16'bZ;

	if(q == STATE_READ) dout_r <= sd_data;

	if(reset) begin
		sd_ba <= 0;
		if(q == STATE_CMD_START) begin
			if(reset == 13) begin
				sd_cmd <= CMD_PRECHARGE;
				sd_addr <= 13'b0010000000000;
			end
			if(reset == 2) begin
				sd_cmd <= CMD_LOAD_MODE;
				sd_addr <= MODE;
			end
		end
	end
	else begin
		if(refresh && !last_refresh) sd_cmd <= CMD_AUTO_REFRESH;

		if(ce && !last_ce) begin
			sd_cmd  <= CMD_ACTIVE;
			sd_ba   <= addr[22:21];
			sd_addr <= addr[20:8];
			caddr   <= {addr[23], addr[7:0]};
			bt      <= addr[24];
			wr      <= we;
			wrdata  <= din;
		end
		if(q == STATE_CMD_CONT) begin
			if(wr) sd_data <= {wrdata, wrdata};
			sd_cmd  <= wr ? CMD_WRITE : CMD_READ;
			sd_addr <= {~bt & wr, bt & wr, 2'b10, caddr};
		end
	end
end

altddio_out
#(
	.extend_oe_disable("OFF"),
	.intended_device_family("Cyclone V"),
	.invert_output("OFF"),
	.lpm_hint("UNUSED"),
	.lpm_type("altddio_out"),
	.oe_reg("UNREGISTERED"),
	.power_up_high("OFF"),
	.width(1)
)
sdramclk_ddr
(
	.datain_h(1'b0),
	.datain_l(1'b1),
	.outclock(clk),
	.dataout(sd_clk),
	.aclr(1'b0),
	.aset(1'b0),
	.oe(1'b1),
	.outclocken(1'b1),
	.sclr(1'b0),
	.sset(1'b0)
);

endmodule
