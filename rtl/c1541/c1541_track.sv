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

function [7:0] bitSwap8(input [7:0] data);
	integer i;
	for (i = 0; i < 8; i = i + 1) begin
		bitSwap8[7 - i] = data[i];
	end
endfunction
function [63:0] bitSwap64(input [63:0] data);
	bitSwap64 = {
		data[ 7: 0],
		data[15: 8],
		data[23:16],
		data[31:24],
		data[39:32],
		data[47:40],
		data[55:48],
		data[63:56]
        };
endfunction

assign sd_buff_din = metadata_track ? sd_metadata_buff_din :
		     sd_to_buffer == 0 ? bitSwap8(sd_track_buff0_din) :
					 bitSwap8(sd_track_buff1_din);
wire [7:0] swapped_sd_buff_dout = bitSwap8(sd_buff_dout);

wire sd_b_ack = sd_ack & busy;
reg [15:0] buff_bit_addr;
wire [15:0] next_buff_bit_addr = buff_bit_addr + 16'b1;
wire [15:0] next_buff_bit_addr_wrapped = next_buff_bit_addr[15:3] < track_length ? next_buff_bit_addr : 16'b0;
wire [3:0] buff_last_lba = track_length[15:12];
wire [3:0] lba_count_to_next_track_lba = (buff_last_lba == buff_bit_addr[15:12] ? ~buff_bit_addr[15:12] : 4'b0) + 4'b1;
wire [3:0] buff_bit_addr_lba = buff_bit_addr[15:12];
wire [3:0] next_buff_bit_addr_wrapped_lba = next_buff_bit_addr_wrapped[15:12];
wire buff_din_posedge = buff_we && !old_buff_din && buff_din;
reg old_buff_din;
reg buff_din_latched;

reg sd_to_buffer = 0;
reg head_to_buffer = 0;
wire flux_change = head_to_buffer == 0 ? flux_change0 : flux_change1;

wire [7:0] sd_track_buff0_din;
wire flux_change0;
dpram_difclk #(.addr_width_a(13), .data_width_a(8), .addr_width_b(16), .data_width_b(1)) buffer0
(
	.clock0(sd_clk),
	.address_a({sd_buff_base, sd_buff_addr}),
	.data_a(swapped_sd_buff_dout),
	.enable_a(1'b1),
	.wren_a(sd_b_ack && sd_buff_wr && !metadata_track && sd_to_buffer == 0),
	.q_a(sd_track_buff0_din),
	.cs_a(1'b1),

	.clock1(clk),
	.address_b(buff_bit_addr),
	.enable_b(1'b1),
	.data_b(buff_din_latched),
	.wren_b(buff_we && head_to_buffer == 0),
	.q_b(flux_change0),
	.cs_b(1'b1)
);

wire [7:0] sd_track_buff1_din;
wire flux_change1;
dpram_difclk #(.addr_width_a(13), .data_width_a(8), .addr_width_b(16), .data_width_b(1)) buffer1
(
	.clock0(sd_clk),
	.address_a({sd_buff_base, sd_buff_addr}),
	.data_a(swapped_sd_buff_dout),
	.enable_a(1'b1),
	.wren_a(sd_b_ack && sd_buff_wr && !metadata_track && sd_to_buffer == 1),
	.q_a(sd_track_buff1_din),
	.cs_a(1'b1),

	.clock1(clk),
	.address_b(buff_bit_addr),
	.enable_b(1'b1),
	.data_b(buff_din_latched),
	.wren_b(buff_we && head_to_buffer == 1),
	.q_b(flux_change1),
	.cs_b(1'b1)
);

wire [7:0] sd_metadata_buff_din;
wire [63:0] metadata_buffer_64;
wire [1:0] freq; // XXX: unused
wire [13:0] bit_clock_delay; // 6.8 fixed-point
wire [15:0] track_length;
wire [15:0] previous_track_length_ratio; // 1.15 fixed-point
wire [15:0] next_track_length_ratio; // 1.15 fixed-point
assign {freq, bit_clock_delay, track_length, previous_track_length_ratio, next_track_length_ratio} = bitSwap64(metadata_buffer_64);
dpram_difclk #(.addr_width_a(10), .data_width_a(8), .addr_width_b(7), .data_width_b(64)) metadata_buffer
(
	.clock0(sd_clk),
	.address_a({sd_buff_base[0], sd_buff_addr}),
	.enable_a(1'b1),
	.data_a(sd_buff_dout),
	.wren_a(sd_b_ack & sd_buff_wr & metadata_track),
	.q_a(sd_metadata_buff_din),
	.cs_a(1'b1),

	.clock1(clk),
	.address_b(cur_half_track),
	.enable_b(1'b1),
	// XXX: no drive-side write support: drive will not be able to resize tracks, and will write at pre-existing track speed.
	.data_b(),
	.wren_b(1'b0),
	.q_b(metadata_buffer_64),
	.cs_b(1'b1)
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

reg is_current_lba_dirty = 0;
reg [3:0] dirty_lba_count = 0;
wire [3:0] next_dirty_lba_count = &dirty_lba_count ? dirty_lba_count : (dirty_lba_count + (is_current_lba_dirty ? lba_count_to_next_track_lba : 4'b0));

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
	reg [3:0] lba_count; // zero-complement of the number of LBAs to write to sd

	old_disk_change <= disk_change;
	if (~old_disk_change && disk_change) ready <= 1;

	old_buff_din <= buff_din;
	if (ready && mtr) begin
		if (clk_counter == clk_counter_max_integer) begin
			// number of 32MHz clock periods until next bit is: next_delay = track_delay * 2 + (32 * 2 - 1).next_delay_fract
			// "32" because track_delay is stored offset by -32.
			// "* 2" because our clock is 32 MHz, while track delay is in 16MHz cycles.
			// "- 1" because we are already one 32MHz cycle into the next bit.
			// Note: clk_counter_max_fractional[0] is always 0 and is optimised away during synthesis, but removing it here makes the "* 2" harder to notice.
			{clk_counter_max_integer, clk_counter_max_fractional} <= {1'b0, bit_clock_delay, 1'b0} + {8'd63, clk_counter_max_fractional};
			buff_bit_addr <= next_buff_bit_addr_wrapped;
			if (buff_bit_addr_lba != next_buff_bit_addr_wrapped_lba) begin // moving to next LBA on next bit address increment ...
				if (next_dirty_lba_count) begin // ... and we have some dirty LBAs
					if (busy) begin // ... which cannot be written back yet, keep counting
						dirty_lba_count <= next_dirty_lba_count;
					end else begin // ... which can be written back now
						saving <= 1;
						sd_buff_base <= buff_bit_addr_lba - next_dirty_lba_count;
						lba_count <= ~next_dirty_lba_count;
						wr <= 1;
						busy <= 1;
						dirty_lba_count <= 0;
					end
				end
				is_current_lba_dirty <= 0;
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
			end else if (clk_counter == 8'd8) begin
				buff_dout <= 0;
			end
			buff_din_latched <= buff_din_latched || buff_din_posedge;
			is_current_lba_dirty <= (is_current_lba_dirty || buff_we) && !disk_change;
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
		sd_to_buffer <= 0;
		head_to_buffer <= 0;
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
				// Move sd to the buffer the head is currently on.
				sd_to_buffer <= head_to_buffer;
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
		if (next_dirty_lba_count && cur_half_track != half_track) begin
			saving <= 1;
			sd_buff_base <= buff_bit_addr_lba - next_dirty_lba_count;
			lba_count <= ~next_dirty_lba_count;
			wr <= 1;
			busy <= 1;
			is_current_lba_dirty <= 0;
			dirty_lba_count <= 0;
			// Move head to the other buffer, keep sd on current buffer for writeback
			head_to_buffer <= head_to_buffer + 1'b1;
		end else if (
			(cur_half_track != half_track) ||
			(old_disk_change && !disk_change)
		) begin
			saving <= 0;
			if (old_disk_change && !disk_change) begin
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
			// Reuse current buffer
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
