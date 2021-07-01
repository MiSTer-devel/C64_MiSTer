//============================================================================
//
//  RTC PCF8583
//  Copyright (C) 2021 Alexey Melnikov
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
//============================================================================

module rtcF83 #(parameter CLOCK_RATE, HAS_RAM = 1)
(
	input        clk,
	input        ce,
	input        reset,

	input [64:0] RTC,
	
	input        scl_i,
	input        sda_i,
	output reg   sda_o
);

localparam CTL  = 0;
localparam FSEC = 1;
localparam SEC  = 2;
localparam MIN  = 3;
localparam HR   = 4;
localparam DATE = 5;
localparam MON  = 6;
localparam YEAR = 16;

wire [7:0] year = {1'b0,RTC[47:44],3'b000} + {3'b000,RTC[47:44],1'b0} + RTC[43:40];
wire [7:0] hr   = {1'b0,RTC[23:20],3'b000} + {3'b000,RTC[23:20],1'b0} + RTC[19:16];
wire [7:0] hrh  = (hr >= 12) ? (hr - 8'd12) : hr;
wire [5:0] hr12 = (!hrh) ? 6'h12 : (hrh == 11) ? 6'h11 : (hrh == 10) ? 6'h10 : hrh[5:0];
wire       pm   = (hr >= 12);

always @(posedge clk) begin
	reg  [1:0] sda_sr, scl_sr;
	reg        old_sda, old_scl;
	reg        sda, scl;
	reg  [7:0] tmp;
	reg  [3:0] cnt = 0;
	reg [10:0] bcnt = 0;
	reg        ack;
	reg        i2c_rw;
	reg  [7:0] ptr;
	reg  [7:0] data[256];
	reg  [7:0] tm[17];
	reg        flg = 0;
	reg [31:0] seccnt = 1;
	reg  [7:0] scl_d;
	reg  [7:0] sda_d;
	reg  [7:0] bt;

	bt <= HAS_RAM ? data[ptr] : 8'h00;

	if(reset) begin
		sda_o <= 1;
		ptr <= 0;
		cnt <= 0;
	end
	else begin
		sda_sr <= {sda_sr[0],sda_i};
		if(sda_sr[0] == sda_sr[1]) sda <= sda_sr[1];
		old_sda <= sda;
		sda_d <= (sda_d << 1) | sda;

		scl_sr <= {scl_sr[0],scl_i};
		if(scl_sr[0] == scl_sr[1]) scl <= scl_sr[1];
		old_scl <= scl;
		scl_d <= (scl_d << 1) | scl;

		//start
		if(old_scl & scl & old_sda & ~sda) begin
			cnt <= 9;
			bcnt <= 0;
			ack <= 0;
			i2c_rw <= 0;
		end

		//stop
		if(old_scl & scl & ~old_sda & sda) begin
			cnt <= 0;
		end

		//data latch
		if(~old_scl && scl && cnt) begin
			tmp <= {tmp[6:0], sda};
			cnt <= cnt - 1'd1;
		end

		if(!cnt) sda_o <= 1;

		//data set
		if(old_scl && ~scl) begin
			sda_o <= 1;
			if(cnt == 1) begin
				if(!bcnt) begin
					if(tmp[7:1] == 'h50) begin
						sda_o <= 0;
						ack <= 1;
						i2c_rw <= tmp[0];
						bcnt <= bcnt + 1'd1;
						cnt <= 10;
					end
					else begin
						// wrong address, stop
						cnt <= 0;
					end
				end
				else if(ack) begin
					ptr <= ptr + 1'd1;
					if(~i2c_rw) begin
						if(bcnt == 1) ptr <= tmp;
						if(ptr<=16) tm[ptr] <= tmp;
						else if(HAS_RAM) data[ptr] <= tmp;
					end
					if(~&bcnt) bcnt <= bcnt + 1'd1;
					sda_o <= 0;
					cnt <= 10;
				end
			end
			else if(i2c_rw && ack && cnt) begin
				sda_o <= (ptr<=16) ? tm[ptr][cnt[2:0] - 2'd2] : bt[cnt[2:0] - 2'd2];
			end
		end
	end

	if(ce) begin
		seccnt <= seccnt + 1;
		if(seccnt >= CLOCK_RATE/100) begin
			seccnt <= 1;
			if(!tm[CTL][7]) begin
				if (tm[FSEC][3:0] != 9) tm[FSEC][3:0] <= tm[FSEC][3:0] + 1'd1;
				else begin
					tm[FSEC][3:0] <= 0;
					if (tm[FSEC][7:4] != 9) tm[FSEC][7:4] <= tm[FSEC][7:4] + 1'd1;
					else begin
						tm[FSEC][7:4] <= 0;
						if (tm[SEC][3:0] != 9) tm[SEC][3:0] <= tm[SEC][3:0] + 1'd1;
						else begin
							tm[SEC][3:0] <= 0;
							if (tm[SEC][7:4] != 5) tm[SEC][7:4] <= tm[SEC][7:4] + 1'd1;
							else begin
								tm[SEC][7:4] <= 0;
								if (tm[MIN][3:0] != 9) tm[MIN][3:0] <= tm[MIN][3:0] + 1'd1;
								else begin
									tm[MIN][3:0] <= 0;
									if (tm[MIN][7:4] != 5) tm[MIN][7:4] <= tm[MIN][7:4] + 1'd1;
									else begin
										tm[MIN][7:4] <= 0;
										if (tm[HR][3:0] == 9) begin
											tm[HR][3:0] <= 0;
											tm[HR][5:4] <= tm[HR][5:4] + 1'd1;
										end
										else if (tm[HR] == {2'b10,6'h12}) begin
											tm[HR][3:0] <= 1;
											tm[HR][5:4] <= 1;
										end
										else if ((tm[HR] != {2'b11,6'h12}) && (tm[HR] != 8'h23)) tm[HR][3:0] <= tm[HR][3:0] + 1'd1;
										else begin
											if (tm[HR][7]) tm[HR][6:0] <= 1;
											else tm[HR][6:0] <= 0;
											
											tm[MON][7:5] <= (tm[MON][7:5] == 6) ? 3'd0 : (tm[MON][7:5] + 1'd1);

											if (({tm[MON][4:0], 2'b00, tm[DATE][5:0]} == 13'h0228) ||
												 ({tm[MON][4:0], 2'b00, tm[DATE][5:0]} == 13'h0430) ||
												 ({tm[MON][4:0], 2'b00, tm[DATE][5:0]} == 13'h0630) ||
												 ({tm[MON][4:0], 2'b00, tm[DATE][5:0]} == 13'h0930) ||
												 ({tm[MON][4:0], 2'b00, tm[DATE][5:0]} == 13'h1130) ||
												 (tm[DATE][5:0] == 6'h31)) begin
												
												tm[DATE][5:0] <= 1;
												if (tm[MON][3:0] == 9) tm[MON][4:0] <= 'h10;
												else if (tm[MON][4:0] != 'h12) tm[MON][3:0] <= tm[MON][3:0] + 1'd1;
												else begin 
													tm[MON][4:0] <= 1;
													tm[DATE][7:6] <= tm[DATE][7:6] + 1'd1;
												end
											end
											else if (tm[DATE][3:0] != 9) tm[DATE][3:0] <= tm[DATE][3:0] + 1'd1;
											else begin
												tm[DATE][3:0] <= 0;
												tm[DATE][5:4] <= tm[DATE][5:4] + 1'd1;
											end
										end
									end
								end
							end
						end
					end
				end
			end
		end
	end

	flg <= RTC[64];
	if (flg != RTC[64]) begin
		tm[CTL]  <= 0;
		tm[FSEC] <= 0;
		tm[SEC]  <= RTC[6:0];
		tm[MIN]  <= RTC[15:8];
		tm[HR]   <= {1'b1,pm, hr12};
		tm[DATE] <= {year[1:0],RTC[29:24]};
		tm[MON]  <= {RTC[50:48],RTC[36:32]};
		tm[YEAR] <= year;
		seccnt   <= 1;
	end
end

endmodule
