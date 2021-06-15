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
	
	input         gcr_mode,

	output [31:0] sd_lba,
	output  [5:0] sd_blk_cnt,
	output reg    sd_rd,
	output reg    sd_wr,
	input         sd_ack,

	input         save_track,
	input         change,
	input   [6:0] track,
	output reg    busy
);

assign sd_lba     = lba;
assign sd_blk_cnt = gcr_mode ? 6'h1F : len[5:0];

wire [6:0] track_s;
wire       change_s, save_track_s, reset_s;

iecdrv_sync #(7) track_sync  (clk, track,      track_s);
iecdrv_sync #(1) change_sync (clk, change,     change_s);
iecdrv_sync #(1) save_sync   (clk, save_track, save_track_s);
iecdrv_sync #(1) reset_sync  (clk, reset,      reset_s);

wire [9:0] start_sectors[41] =
'{  0, 21, 42, 63, 84,105,126,147,168,189,210,231,252,273,294,315,336,357,376,395,
  414,433,452,471,490,508,526,544,562,580,598,615,632,649,666,683,700,717,734,751,
  768
};

reg [31:0] lba;
reg  [9:0] len;

always @(posedge clk) begin
	reg  [6:0] cur_track = 0;
	reg  [6:0] track_new;
	reg        old_change, update = 0;
	reg        saving = 0, initing = 0;
	reg        old_save_track = 0;
	reg        old_ack;

	// delay track change after sync, so make sure save_track comes first.
	track_new <= gcr_mode ? track_s : track_s[6:1];

	old_change <= change_s;
	if(~old_change & change_s) update <= 1;
	
	old_ack <= sd_ack;
	if(sd_ack) {sd_rd,sd_wr} <= 0;

	if(reset_s) begin
		cur_track <= '1;
		busy      <= 0;
		sd_rd     <= 0;
		sd_wr     <= 0;
		saving    <= 0;
		update    <= 1;
	end
	else if(busy) begin
		if(old_ack && ~sd_ack) begin
			if((initing || saving) && (cur_track != track_new)) begin
				saving    <= 0;
				initing   <= 0;
				cur_track <= track_new;
				len       <= start_sectors[track_new+1'd1] - start_sectors[track_new] - 1'd1;
				lba       <= gcr_mode ? track_new : start_sectors[track_new];
				sd_rd     <= 1;
			end
			else begin
				busy      <= 0;
			end
		end
	end
	else begin
		old_save_track <= save_track_s;
		if((old_save_track ^ save_track_s) && ~&cur_track[6:1]) begin
			saving    <= 1;
			len       <= start_sectors[cur_track+1'd1] - start_sectors[cur_track] - 1'd1;
			lba       <= gcr_mode ? cur_track : start_sectors[cur_track];
			sd_wr     <= 1;
			busy      <= 1;
		end
		else if(update & ~gcr_mode) begin
			update    <= 0;
			initing   <= 1;
			cur_track <= 17;
			len       <= start_sectors[17+1] - start_sectors[17] - 1'd1;
			lba       <= start_sectors[17];
			sd_rd     <= 1;
			busy      <= 1;
		end
		else if(cur_track != track_new || (update & gcr_mode)) begin
			cur_track <= track_new;
			len       <= start_sectors[track_new+1'd1] - start_sectors[track_new] - 1'd1;
			lba       <= gcr_mode ? track_new : start_sectors[track_new];
			sd_rd     <= 1;
			busy      <= 1;
			update    <= 0;
		end
	end
end

endmodule
