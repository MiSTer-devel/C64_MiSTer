//-------------------------------------------------------------------------------
//
// C1541 direct gcr module
// (C) 2021 Alexey Melnikov
//
//
// disk rotation and low level read logic based on schematics by Robin Wünderlich
// TODO:
// - investigate potential T65 inaccurate so_n handling (e.g. not preventing
// so_n sampling for upto 2 cycles into next instruction after an instruction
// sets/clears overflow)
// - improve support code speed of track data delivery
//-------------------------------------------------------------------------------

module c1541_direct_gcr
(
	input        clk,
	input        ce,
	input        reset,

	input  [2:0] drive_rpm,
	input        drive_wobble,

	output [7:0] dout,
	input  [7:0] din,
	input        mode,
	input        mtr,
	input  [1:0] freq,
	input        wps_n,
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

assign we          = buff_we;
assign sd_buff_din = (sd_buff_addr >= track_len_adj + 2) ? 8'hFF : sd_buff_do;
assign dout        = shreg[7:0];

reg [12:0] track_len, track_new, len_valid;
always @(posedge sd_clk) if(sd_buff_wr && !sd_buff_addr[13:1]) begin
	// size and possible flags
	if(sd_buff_addr[0] == 0) track_new[7:0]  <= sd_buff_dout;
	if(sd_buff_addr[0] == 1) track_new[12:8] <= sd_buff_dout[4:0];
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
	.data_b(ht),
	.wren_b(buff_we),
	.q_b(buff_do)
);

reg  [15:0] buff_addr;
reg   [7:0] buff_di;
wire        buff_do;
reg         buff_we;

wire [30:0] random_data;
random lfsr(
   .clock(clk),
   .lfsr(random_data)
);

// 1541 part designations are based on the schematics in:
// "Commodore 1541 Troubleshooting & Repair Guide – M. Peltier".
// the UC1 chip integrates several discrete 1540 parts,
// which are referenced by their 1540 designations
assign sync_n = ~&shreg | ~mode;                               // UC2  (UC1)
assign byte_n = ~&UE3_bit_cnt | &shreg | UF4_enc_phase_cnt[1]; // UF3C (UC1) (soe: c1541_logic)
reg  [9:0] shreg;              // UD2 74LS164, UE4A+UE4B 74LS74 (UC1)
reg  [3:0] UF4_enc_phase_cnt;  // 74LS193 (UC1)
reg  [3:0] UE6_enc_clk_cnt;    // 74LS193
reg  [2:0] UE3_bit_cnt;        // 74LS191 (UC1)
reg  [2:0] UD3_bit_cnt_w;      // 74LS165 (UC1)
reg  [5:0] UD4A_cnt;           // 9602
reg  [8:0] flux_cnt;
reg        hf;                 // data from head
reg        ht;                 // data to head

// clks per bitcell in relation to track length:
// = (CLK_FREQ / (8 * (BASE_RPM/60))) / track_len
// -> BASE_ROT_TARGET = 400_000 (+/- wobble)
// wobble will vary slightly for other rpm settings
localparam        BASE_RPM         =         300;
localparam        CLK_FREQ         =  16_000_000;
localparam        BASE_ROT_TARGET  =     400_000;
localparam        WBL_FREQ         =          43; // WPM* 10
localparam        WBL_MAX          =          21; // RPM*100
localparam        WBL_CLKS_PER_STP = (((CLK_FREQ/(4*WBL_MAX_OFFSET)) * 600) / WBL_FREQ);
localparam signed WBL_MAX_OFFSET   = ((BASE_ROT_TARGET/ 100) * WBL_MAX)/BASE_RPM;

wire [18:0] base_rot_targets[8] = '{19'd400_000, 19'd398_671, 19'd397_351, 19'd393_443,
                                    19'd387_097, 19'd406_780, 19'd402_685, 19'd401_338};

wire       [19:0] rot_target = $signed({1'b0, base_rot_targets[drive_rpm]}) + (drive_wobble ? wbl_offset : 10'sd0);
reg        [19:0] rot_clk_cnt;
reg        [31:0] wbl_step_cnt;
reg signed [9:0]  wbl_offset;
reg               wbl_dir;

// use len_valid as proxy for empty (half) tracks
wire [12:0] track_new_adj = (track_new > 'd6000) ? track_new : len_valid;
wire [12:0] track_len_adj = (track_len > 'd6000) ? track_len : len_valid;
wire [13:0] recip = rec[track_len_adj-6000];

// precalc reciprocals for track_len_adj = 6000 .. 8047
reg  [13:0] rec[0:2047];
initial begin
	integer i;
	for(i = 0; i < 2048; i = i + 1) begin
		rec[i] = 14'((1 << 26) / (i + 6000));
	end
end

always @(posedge clk) begin
	buff_we <= 0;

	if(reset) begin
		buff_addr           <= 16;
		UE3_bit_cnt         <= 0;
		UD3_bit_cnt_w       <= 0;
		shreg               <= 0;
		hf                  <= 0;
		ht                  <= 0;
		rot_clk_cnt         <= 0;
		UF4_enc_phase_cnt   <= 0;
		UE6_enc_clk_cnt     <= 0;
		UD4A_cnt            <= 0;
		flux_cnt            <= 9'd288;
		wbl_offset          <= 0;
		wbl_step_cnt        <= 0;
		wbl_dir             <= 0;
		track_len           <= 0;
		len_valid           <= 'd7142;
	end
	else if(busy) begin
	end
	else if(ce) begin

		// simulate independent rotation of disk (usually at 300RPM):
		// let drive read logic self sync on the data,
		// if writing, synchronize to encoder/decoder phase
		if(mode) begin
			if(rot_clk_cnt >= rot_target) begin
				rot_clk_cnt <=  rot_clk_cnt - rot_target + track_len_adj;
				if(track_new == track_len) begin
					if(buff_addr >= {track_len_adj + 1'd1, 3'b111})
						buff_addr <= 16'd16;
					else begin
						buff_addr <=  buff_addr + 1'd1;
					end
				end
			end else if(mtr)
				rot_clk_cnt <= rot_clk_cnt + track_len_adj;
				else rot_clk_cnt <= 0;
		end else
			if(&UE6_enc_clk_cnt && (UF4_enc_phase_cnt[1:0] == 2'b01)) begin
				if(buff_addr >= {track_len + 1'd1, 3'b111}) buff_addr <= 16;
				else buff_addr <=  buff_addr + 1'd1;
			end

		// drivers of hf (flux reversals from data, or random flux reversals)
		if(!mode)                          hf <= 0;
		else if(!flux_cnt)                 hf <= 1;
		else if(busy)                      hf <= 0;
		else if(track_len <= 6000)         hf <= 0;
		else if(rot_clk_cnt >= rot_target) hf <= buff_do;
		else                               hf <= 0;  // demux dogma

		// random flux reversal counters (weak bits/bad gcr)
		if(hf) begin
			if(!flux_cnt)  flux_cnt <= random_data[7:0] + 9'd37;
			else           flux_cnt <= random_data[4:0] + 9'd288;
		end
		else if(flux_cnt) flux_cnt <= flux_cnt - 1'b1;

		// encoder-decoder clock divider based on freq
		if(&UE6_enc_clk_cnt) begin
			UE6_enc_clk_cnt <= {2'b00,freq};
		end else
			UE6_enc_clk_cnt <= UE6_enc_clk_cnt + 1'b1;

		// encoder-decoder
		// flux reversals reset (see filter stage below) UE6 and UF4 counters
		// a one bit will be clocked into the shift register in phase b0010.
		// if the allowed time window expires without a flux reversal 0 bits
		// will be clocked into the shift register (phases b0110, b1010 etc.)
		if(&UE6_enc_clk_cnt) begin
			UF4_enc_phase_cnt <= UF4_enc_phase_cnt + 1'b1;
			// transition into phase bxx10
			if(UF4_enc_phase_cnt[1:0] == 2'b01) begin
				shreg          <= {shreg[8:0], ~|UF4_enc_phase_cnt[3:2]}; // UE5a (UC1)
				UE3_bit_cnt    <= UE3_bit_cnt   + 1'b1;
				UD3_bit_cnt_w  <= UD3_bit_cnt_w + 1'b1;
			end
			// transition into phase bxx11
			else if((UF4_enc_phase_cnt[1:0] == 2'b10) && (&UE3_bit_cnt)) begin
				buff_di        <= din;
				UD3_bit_cnt_w  <= 0;
			end
			// transition into phase bxx00 (writing)
			else if((UF4_enc_phase_cnt[1:0] == 2'b11)) begin
				if(!mode) begin
					ht <= buff_di[~UD3_bit_cnt_w];
					if(wps_n) buff_we <= ~mode;
				end
			end
		end

		// detected flux reversals are validated by a filter stage
		// as we only model valid flux reversals the effect is a
		// 2.5us delay (40clks = 64-24) of the UE6/UF4 counter reset
		if (UD4A_cnt) begin
			UD4A_cnt <= UD4A_cnt + 1'b1;
			if (&UD4A_cnt) begin
				UE6_enc_clk_cnt   <= {2'b00,freq};
				UF4_enc_phase_cnt <= 0;
			end
		end else if(hf) UD4A_cnt <= 6'd24;

		if(~sync_n) UE3_bit_cnt <= 0;

		// drive wobble
		if(wbl_step_cnt >= WBL_CLKS_PER_STP) begin
			wbl_step_cnt <= 0;
			wbl_dir      <= (wbl_offset >  WBL_MAX_OFFSET) ? 1'b0 :
                         (wbl_offset < -WBL_MAX_OFFSET) ? 1'b1 :
                          wbl_dir;
			wbl_offset   <= wbl_offset + (wbl_dir ? 10'sd1 : -10'sd1);
		end else
			wbl_step_cnt <= wbl_step_cnt + 1'b1;

		// adjustment for disk geometry if head moves to new track
		// use valid length of neighbouring track as proxy for empty track
		track_len <= track_new;
		if(track_new != track_len) begin
			if(track_new > 'd6000) len_valid <= track_new;
			buff_addr <= 16'(((43'h0 + ((buff_addr - 16) * track_new_adj)) * recip) >> 26) + 16'd16;
		end
	end
end

endmodule
