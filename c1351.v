////////////////////////////////////////////////////////////////////////////////
//
//  C1351 Mouse
//  (C) 2019 Sorgelig
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//
////////////////////////////////////////////////////////////////////////////////

module c1351
(
	input        clk_sys,
	input        reset,

	input [24:0] ps2_mouse,
	
	output [7:0] potX,
	output [7:0] potY,
	output [1:0] button
);

reg [16:0] lfsr;
always @(posedge clk_sys) lfsr <= {(lfsr[0] ^ lfsr[2] ^ !lfsr), lfsr[16:1]};

assign potX = ~{1'b0, x, lfsr[0]};
assign potY = ~{1'b0, y, lfsr[8]};
assign button = ps2_mouse[1:0];

reg [5:0] x;
reg [5:0] y;

always @(posedge clk_sys) begin
	reg old_status;
	
	old_status <= ps2_mouse[24];

	if(reset) begin
		x <= 0;
		y <= 0;
	end else begin
		if(old_status != ps2_mouse[24]) begin
			x <= x + ps2_mouse[13:8];
			y <= y + ps2_mouse[21:16];
		end
	end
end

endmodule
