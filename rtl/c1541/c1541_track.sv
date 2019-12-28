// 
// c1541_track
// Copyright (c) 2016 Sorgelig
//
// This source file is free software: you can redistribute it and/or modify
// it under the terms of the Lesser GNU General Public License as published
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
//
/////////////////////////////////////////////////////////////////////////

module c1541_track
(
	input         clk,
	input         reset,

	input         sd_clk,
	output [31:0] sd_lba,
	output reg    sd_rd,
	output reg    sd_wr,
	input         sd_ack,

	input   [8:0] sd_buff_addr,
	input   [7:0] sd_buff_dout,
	output  [7:0] sd_buff_din,
	input         sd_buff_wr,

	input         disk_change,
	input   [1:0] stp,
	input         mtr,
	output reg    tr00_sense_n,
	output reg    buff_dout,
	input         buff_din,
	input         buff_we,
	output reg    busy
);

always @(posedge sd_clk) begin
	reg wr1,rd1;
	
	wr1 <= wr;
	rd1 <= rd;
	
	sd_wr <= wr1;
	sd_rd <= rd1;
end

wire [62:0] rnd;
lfsr random(rnd);

assign sd_buff_din = ~metadata_track ? sd_track_buff_din :
		     sd_buff_addr[2:0] == 3'b000 ? sd_metadata_buff_din[63:56] :
		     sd_buff_addr[2:0] == 3'b001 ? sd_metadata_buff_din[55:48] :
		     sd_buff_addr[2:0] == 3'b010 ? sd_metadata_buff_din[47:40] :
		     sd_buff_addr[2:0] == 3'b011 ? sd_metadata_buff_din[39:32] :
		     sd_buff_addr[2:0] == 3'b100 ? sd_metadata_buff_din[31:24] :
		     sd_buff_addr[2:0] == 3'b101 ? sd_metadata_buff_din[23:16] :
		     sd_buff_addr[2:0] == 3'b110 ? sd_metadata_buff_din[15: 8] :
						   sd_metadata_buff_din[ 7: 0];

wire sd_b_ack = sd_ack & busy;
reg [15:0] buff_bit_addr;
wire [15:0] next_buff_bit_addr = buff_bit_addr + 16'b1;
wire [15:0] next_buff_bit_addr_wrapped = next_buff_bit_addr[15:3] < track_length ? next_buff_bit_addr : 16'b0;
wire [3:0] buff_bit_addr_lba = buff_bit_addr[15:12];
wire [3:0] next_buff_bit_addr_wrapped_lba = next_buff_bit_addr_wrapped[15:12];
wire [7:0] buff_dout_byte;
wire flux_change = buff_dout_byte[~buff_bit_addr[2:0]];
wire buff_din_posedge = buff_we && !old_buff_din && buff_din;
reg old_buff_din;
reg buff_din_latched;

wire [7:0] sd_track_buff_din;
wire [7:0] buff_din_byte = buff_bit_addr[2:0] == 3'd0 ? {                     buff_din_latched, buff_dout_byte[6:0]} :
			   buff_bit_addr[2:0] == 3'd1 ? {buff_dout_byte[7  ], buff_din_latched, buff_dout_byte[5:0]} :
			   buff_bit_addr[2:0] == 3'd2 ? {buff_dout_byte[7:6], buff_din_latched, buff_dout_byte[4:0]} :
			   buff_bit_addr[2:0] == 3'd3 ? {buff_dout_byte[7:5], buff_din_latched, buff_dout_byte[3:0]} :
			   buff_bit_addr[2:0] == 3'd4 ? {buff_dout_byte[7:4], buff_din_latched, buff_dout_byte[2:0]} :
			   buff_bit_addr[2:0] == 3'd5 ? {buff_dout_byte[7:3], buff_din_latched, buff_dout_byte[1:0]} :
			   buff_bit_addr[2:0] == 3'd6 ? {buff_dout_byte[7:2], buff_din_latched, buff_dout_byte[  0]} :
							{buff_dout_byte[7:1], buff_din_latched                     };
trk_dpram buffer
(
	.clock_a(sd_clk),
	.address_a({sd_buff_base, sd_buff_addr}),
	.data_a(sd_buff_dout),
	.wren_a(sd_b_ack & sd_buff_wr & ~metadata_track),
	.q_a(sd_track_buff_din),

	.clock_b(clk),
	.address_b(buff_bit_addr[15:3]),
	.data_b(buff_din_byte),
	.wren_b(buff_we/* && !busy*/),
	.q_b(buff_dout_byte)
);

wire [63:0] sd_metadata_buff_din;
wire [63:0] sd_metadata_buff_dout = sd_buff_addr[2:0] == 3'b000 ? {                             sd_buff_dout, sd_metadata_buff_din[55:0]} :
				    sd_buff_addr[2:0] == 3'b001 ? {sd_metadata_buff_din[63:56], sd_buff_dout, sd_metadata_buff_din[47:0]} :
				    sd_buff_addr[2:0] == 3'b010 ? {sd_metadata_buff_din[63:48], sd_buff_dout, sd_metadata_buff_din[39:0]} :
				    sd_buff_addr[2:0] == 3'b011 ? {sd_metadata_buff_din[63:40], sd_buff_dout, sd_metadata_buff_din[31:0]} :
				    sd_buff_addr[2:0] == 3'b100 ? {sd_metadata_buff_din[63:32], sd_buff_dout, sd_metadata_buff_din[23:0]} :
				    sd_buff_addr[2:0] == 3'b101 ? {sd_metadata_buff_din[63:24], sd_buff_dout, sd_metadata_buff_din[15:0]} :
				    sd_buff_addr[2:0] == 3'b110 ? {sd_metadata_buff_din[63:16], sd_buff_dout, sd_metadata_buff_din[ 7:0]} :
								  {sd_metadata_buff_din[63: 8], sd_buff_dout                            };
wire [1:0] freq;
wire [13:0] bit_clock_delay; // 6.8 fixed-point
wire [15:0] track_length;
wire [15:0] previous_track_length_ratio; // 1.15 fixed-point
wire [15:0] next_track_length_ratio; // 1.15 fixed-point

trk_dpram #(.DATAWIDTH(64), .ADDRWIDTH(7)) metadata_buffer
(
	.clock_a(sd_clk),
	.address_a({sd_buff_base[0], sd_buff_addr[8:3]}),
	.data_a(sd_metadata_buff_dout),
	.wren_a(sd_b_ack & sd_buff_wr & metadata_track),
	.q_a(sd_metadata_buff_din),

	.clock_b(clk),
	.address_b(cur_half_track),
	// XXX: no drive-side write support: drive will not be able to resize tracks, and will write at pre-existing track speed.
	.data_b(),
	.wren_b(1'b0),
	.q_b({freq, bit_clock_delay, track_length, previous_track_length_ratio, next_track_length_ratio})
);

reg [3:0] sd_buff_base;
reg [6:0] cur_half_track;
wire metadata_track = cur_half_track == 7'd84;
assign sd_lba = {cur_half_track, sd_buff_base};
reg rd,wr;

wire [45:0] previous_scaled_buff_bit_addr_long = {buff_bit_addr, 15'b0} * previous_track_length_ratio; // 16.15 * 1.15 fixed point = 16.30 fixed point result = 46 bits
wire [15:0] previous_scaled_buff_bit_addr = previous_scaled_buff_bit_addr_long[45:30];
wire [45:0] next_scaled_buff_bit_addr_long = {buff_bit_addr, 15'b0} * next_track_length_ratio; // 16.15 * 1.15 fixed point = 16.30 fixed point result = 46 bits
wire [15:0] next_scaled_buff_bit_addr = next_scaled_buff_bit_addr_long[45:30];

// Where a track change should start reading.
// Start reading as close as possible to current head position, but far enough ahead that once it has seen any new-track byte it will not see any old-track byte.
// Assuming tracks are received from hard processor at least 10 times faster than they are read,
// and assuming LBAs are received in increasing sd_buff_addr order,
// it is safe to read the LBA the head is currently on if it is further than 51.2 bytes away from its end. Round it to 64, or when the 3 MSb are 1.
wire [3:0] previous_next_lba = previous_scaled_buff_bit_addr[15:12] + &previous_scaled_buff_bit_addr[11:9];
wire [3:0] next_next_lba = next_scaled_buff_bit_addr[15:12] + &next_scaled_buff_bit_addr[11:9];


always @(posedge clk) begin
	reg ack1,ack2,ack;
	reg old_ack;
	reg old_disk_change, ready = 0;
	reg saving = 0;
	reg [62:0] rnd_reg;
	reg [7:0] clk_counter;
	reg [7:0] clk_counter_max_integer;
	reg [7:0] clk_counter_max_fractional;
	reg [1:0] no_flux_change_count;
	reg [3:0] lba_count;
	reg is_current_lba_dirty = 0;

	old_disk_change <= disk_change;
	if (~old_disk_change && disk_change) ready <= 1;

	old_buff_din <= buff_din;
	if (mtr) begin
		if (clk_counter == clk_counter_max_integer) begin
			// number of 32MHz clock periods until next bit is: next_delay = track_delay * 2 + (32 * 2 - 1).next_delay_fract
			// "32" because track_delay is stored offset by -32.
			// "* 2" because our clock is 32 MHz, while track delay is in 16MHz cycles.
			// "- 1" because we are already one 32MHz cycle into the next bit.
			// Note: clk_counter_max_fractional[0] is always 0 and is optimised away during synthesis, but removing it here makes the "* 2" harder to notice.
			{clk_counter_max_integer, clk_counter_max_fractional} <= {1'b0, bit_clock_delay, 1'b0} + {8'd63, clk_counter_max_fractional};
			buff_bit_addr <= next_buff_bit_addr_wrapped;
			if (buff_bit_addr_lba != next_buff_bit_addr_wrapped_lba) begin
				if (is_current_lba_dirty) begin
					saving <= 1; /// XXX: what if we are already saving (ex: previous LBA took more to send to hard CPU than drive head to exit current one) ?
					sd_buff_base <= buff_bit_addr_lba;
					lba_count <= 4'b1111; // XXX: to just save one LBA
					wr <= 1;
					busy <= 1;
				end
				is_current_lba_dirty <= buff_we & ~disk_change;
			end
			buff_din_latched <= buff_din_posedge;
			rnd_reg <= rnd;
			clk_counter <= 0;
		end else begin
			// Emit current bit. XXX: emitting a flux inversion from counter 1 to 8 is completely arbitrary. Drive electronics do not care about the actual length.
			if (clk_counter == 8'd1) begin
				if (flux_change) begin
					buff_dout <= ~buff_we;// & ~busy;
					no_flux_change_count <= 0;
				end else begin
					if (no_flux_change_count == 2'd3) begin
						buff_dout <= ~buff_we /*& ~busy*/ & rnd_reg[0];
					end else begin
						buff_dout <= 0;
						no_flux_change_count <= no_flux_change_count + 2'b1;
					end
				end
			end else if (clk_counter == 8'd8)
				buff_dout <= 0;
			buff_din_latched <= buff_din_latched | buff_din_posedge;
			is_current_lba_dirty <= (is_current_lba_dirty | buff_we) & ~disk_change;
			clk_counter <= clk_counter + 8'b1;
		end
	end

	ack1 <= sd_b_ack;
	ack2 <= ack1;
	if(ack2 == ack1) ack <= ack1;

	old_ack <= ack;
	if(ack) {rd,wr} <= 0;

	if(reset) begin
		cur_half_track <= 0;
		busy  <= 0;
		rd <= 0;
		wr <= 0;
		saving<= 0;
		is_current_lba_dirty <= 0;
	end
	else
	if(busy) begin
		if(old_ack && ~ack) begin
			if((!metadata_track && !saving && cur_half_track != half_track)) begin
				// Was loading, but track changed. Stop so a new read is initiated.
				busy <= 0;
			end
			else
			if(( metadata_track && lba_count != 4'b1) ||
			   (!metadata_track && lba_count != 4'b1111)) begin
				// Not done yet ? Load/writeback next LBA.
				sd_buff_base <= sd_buff_base + 4'b1;
				lba_count <= lba_count + 4'b1;
				if(saving) wr <= 1;
					else rd <= 1;
			end
			else
			if(metadata_track) begin
				// metadata_track loading done, start loading track data.
				cur_half_track <= half_track;
				sd_buff_base <= 0;
				lba_count <= 0;
				rd <= 1; // metadata_track is only read on disk change.
			end
			else
			if(saving && (cur_half_track != half_track)) begin
				// Was saving and changing track ? Load next track.
				saving <= 0;
				if (cur_half_track < half_track) begin
					buff_bit_addr <= next_scaled_buff_bit_addr;
					sd_buff_base <= next_next_lba;
				end else begin
					buff_bit_addr <= previous_scaled_buff_bit_addr;
					sd_buff_base <= previous_next_lba;
				end
				cur_half_track <= half_track;

				lba_count <= 0;
				rd <= 1;
			end
			else
			begin
				// Done loading track.
				busy <= 0;
			end
		end
	end
	else
	if(ready) begin
		if (is_current_lba_dirty && cur_half_track != half_track) begin
			saving <= 1; /// XXX: what if we are already saving (ex: previous LBA took more to send to hard CPU than drive head to exit current one) ?
			sd_buff_base <= buff_bit_addr_lba;
			lba_count <= 4'b1111; // XXX: to just save one LBA
			wr <= 1;
			busy <= 1;
		end else if (
			(cur_half_track != half_track) ||
			(old_disk_change && ~disk_change)
		) begin
			saving <= 0;
			if (old_disk_change && ~disk_change) begin
				cur_half_track <= 7'd84;
				sd_buff_base <= 0;
			end else begin
				cur_half_track <= half_track;
				if (cur_half_track < half_track) begin
					buff_bit_addr <= next_scaled_buff_bit_addr;
					sd_buff_base <= next_next_lba;
				end else begin
					buff_bit_addr <= previous_scaled_buff_bit_addr;
					sd_buff_base <= previous_next_lba;
				end
			end
			lba_count <= 0;
			rd <= 1;
			busy <= 1;
		end
	end
end

reg [6:0] half_track;
always @(posedge clk) begin
	reg [1:0] stp_r;

	tr00_sense_n <= |half_track;
	stp_r <= stp;

	if (reset) begin
		half_track <= 36;
	end else begin
		if (mtr) begin
			if ((stp_r == 0 && stp == 1)
				|| (stp_r == 1 && stp == 2)
				|| (stp_r == 2 && stp == 3)
				|| (stp_r == 3 && stp == 0)) begin
				if (half_track < 83) half_track <= half_track + 7'b1;
			end

			if ((stp_r == 0 && stp == 3)
				|| (stp_r == 3 && stp == 2)
				|| (stp_r == 2 && stp == 1)
				|| (stp_r == 1 && stp == 0)) begin
				if (half_track) half_track <= half_track - 7'b1;
			end
		end
	end
end
endmodule

module trk_dpram #(parameter DATAWIDTH=8, ADDRWIDTH=13)
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

logic [DATAWIDTH-1:0] ram[0:(1<<ADDRWIDTH)-1];

always_ff@(posedge clock_a) begin
	if(wren_a) begin
		ram[address_a] <= data_a;
		q_a <= data_a;
	end else begin
		q_a <= ram[address_a];
	end
end

always_ff@(posedge clock_b) begin
	if(wren_b) begin
		ram[address_b] <= data_b;
		q_b <= data_b;
	end else begin
		q_b <= ram[address_b];
	end
end

endmodule
