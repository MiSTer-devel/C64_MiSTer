
module sid8580
(
	input         reset,

	input         clk,
	input         ce_1m,

	input         we,
	input   [4:0] addr,
	input   [7:0] data_in,
	output [ 7:0] data_out,

	input   [7:0] pot_x,
	input   [7:0] pot_y,

	input         extfilter_en,
	output [17:0] audio_data
);

// Internal Signals
reg  [7:0] Voice_1_Freq_lo;
reg  [7:0] Voice_1_Freq_hi;
reg  [7:0] Voice_1_Pw_lo;
reg  [3:0] Voice_1_Pw_hi;
reg  [7:0] Voice_1_Control;
reg  [7:0] Voice_1_Att_dec;
reg  [7:0] Voice_1_Sus_Rel;

reg  [7:0] Voice_2_Freq_lo;
reg  [7:0] Voice_2_Freq_hi;
reg  [7:0] Voice_2_Pw_lo;
reg  [3:0] Voice_2_Pw_hi;
reg  [7:0] Voice_2_Control;
reg  [7:0] Voice_2_Att_dec;
reg  [7:0] Voice_2_Sus_Rel;

reg  [7:0] Voice_3_Freq_lo;
reg  [7:0] Voice_3_Freq_hi;
reg  [7:0] Voice_3_Pw_lo;
reg  [3:0] Voice_3_Pw_hi;
reg  [7:0] Voice_3_Control;
reg  [7:0] Voice_3_Att_dec;
reg  [7:0] Voice_3_Sus_Rel;

reg  [7:0] Filter_Fc_lo;
reg  [7:0] Filter_Fc_hi;
reg  [7:0] Filter_Res_Filt;
reg  [7:0] Filter_Mode_Vol;

wire[17:0] sound;

wire [7:0] Misc_Osc3_Random;
wire [7:0] Misc_Env3;

reg  [7:0] do_buf;
reg  [7:0] sidrandom;

wire [11:0] voice_1;
wire [11:0] voice_2;
wire [11:0] voice_3;
wire [17:0] voice_mixed;
reg  [17:0] voice_volume;

wire        voice_1_PA_MSB;
wire        voice_2_PA_MSB;
wire        voice_3_PA_MSB;

wire [18:0] filtered_audio;
wire [17:0] unsigned_audio;
wire [18:0] unsigned_filt;

localparam DC_offset = 14'b00111111111111;

reg [7:0] _st_out[3];
reg [7:0] p_t_out[3];
reg [7:0] ps__out[3];
reg [7:0] pst_out[3];
wire [11:0] acc_ps[3];
wire [11:0] acc_t[3];

// Voice 1 Instantiation
sid_voice v1
(
	.clock(clk),
	.ce_1m(ce_1m),
	.reset(reset),
	.freq_lo(Voice_1_Freq_lo),
	.freq_hi(Voice_1_Freq_hi),
	.pw_lo(Voice_1_Pw_lo),
	.pw_hi(Voice_1_Pw_hi),
	.control(Voice_1_Control),
	.att_dec(Voice_1_Att_dec),
	.sus_rel(Voice_1_Sus_Rel),
	.osc_msb_in(voice_3_PA_MSB),
	.osc_msb_out(voice_1_PA_MSB),
	.signal_out(voice_1),
	._st_out(_st_out[0]),
	.p_t_out(p_t_out[0]),
	.ps__out(ps__out[0]),
	.pst_out(pst_out[0]),
	.acc_ps(acc_ps[0]),
	.acc_t(acc_t[0])
);

// Voice 2 Instantiation
sid_voice v2
(
	.clock(clk),
	.ce_1m(ce_1m),
	.reset(reset),
	.freq_lo(Voice_2_Freq_lo),
	.freq_hi(Voice_2_Freq_hi),
	.pw_lo(Voice_2_Pw_lo),
	.pw_hi(Voice_2_Pw_hi),
	.control(Voice_2_Control),
	.att_dec(Voice_2_Att_dec),
	.sus_rel(Voice_2_Sus_Rel),
	.osc_msb_in(voice_1_PA_MSB),
	.osc_msb_out(voice_2_PA_MSB),
	.signal_out(voice_2),
	._st_out(_st_out[1]),
	.p_t_out(p_t_out[1]),
	.ps__out(ps__out[1]),
	.pst_out(pst_out[1]),
	.acc_ps(acc_ps[1]),
	.acc_t(acc_t[1])
);

// Voice 3 Instantiation
sid_voice v3
(
	.clock(clk),
	.ce_1m(ce_1m),
	.reset(reset),
	.freq_lo(Voice_3_Freq_lo),
	.freq_hi(Voice_3_Freq_hi),
	.pw_lo(Voice_3_Pw_lo),
	.pw_hi(Voice_3_Pw_hi),
	.control(Voice_3_Control),
	.att_dec(Voice_3_Att_dec),
	.sus_rel(Voice_3_Sus_Rel),
	.osc_msb_in(voice_2_PA_MSB),
	.osc_msb_out(voice_3_PA_MSB),
	.signal_out(voice_3),
	.osc_out(Misc_Osc3_Random),
	.env_out(Misc_Env3),
	._st_out(_st_out[2]),
	.p_t_out(p_t_out[2]),
	.ps__out(ps__out[2]),
	.pst_out(pst_out[2]),
	.acc_ps(acc_ps[2]),
	.acc_t(acc_t[2])
);

// Filter Instantiation
sid_filters filters
(
	.clk(clk),
	.rst(reset),
	.Fc_lo(Filter_Fc_lo),
	.Fc_hi(Filter_Fc_hi),
	.Res_Filt(Filter_Res_Filt),
	.Mode_Vol(Filter_Mode_Vol),
	.voice1(voice_1),
	.voice2(voice_2),
	.voice3(voice_3),
	.input_valid(ce_1m),
	.ext_in(12'hfff),
	.sound(sound),
	.extfilter_en(extfilter_en)
);

sid_tables sid_tables
(
	.clock(clk),
	.acc_ps(f_acc_ps),
	.acc_t(f_acc_t),
	._st_out(f__st_out),
	.p_t_out(f_p_t_out),
	.ps__out(f_ps__out),
	.pst_out(f_pst_out)
);

wire [7:0] f__st_out;
wire [7:0] f_p_t_out;
wire [7:0] f_ps__out;
wire [7:0] f_pst_out;
reg [11:0] f_acc_ps;
reg [11:0] f_acc_t;

always @(posedge clk) begin
	reg [3:0] state;
	
	if(~&state) state <= state + 1'd1;;
	if(ce_1m) state <= 0;

	case(state)
		1,5,9: begin
			f_acc_ps <= acc_ps[state[3:2]];
			f_acc_t  <= acc_t[state[3:2]];
		end
	endcase

	case(state)
		3,7,11: begin
			_st_out[state[3:2]] <= f__st_out;
			p_t_out[state[3:2]] <= f_p_t_out;
			ps__out[state[3:2]] <= f_ps__out;
			pst_out[state[3:2]] <= f_pst_out;
		end
	endcase
end


assign data_out = do_buf;

reg [7:0] last_wr;
always @(*) begin
	case (addr)
		  5'h19: do_buf = pot_x;
		  5'h1a: do_buf = pot_y;
		  5'h1b: do_buf = Misc_Osc3_Random;
		  5'h1c: do_buf = Misc_Env3;
		default: do_buf = last_wr;
	endcase
end


// Register Decoding
reg dac_mode;
always @(posedge clk) begin
	if (reset) begin
		Voice_1_Freq_lo <= 0;
		Voice_1_Freq_hi <= 0;
		Voice_1_Pw_lo   <= 0;
		Voice_1_Pw_hi   <= 0;
		Voice_1_Control <= 0;
		Voice_1_Att_dec <= 0;
		Voice_1_Sus_Rel <= 0;
		Voice_2_Freq_lo <= 0;
		Voice_2_Freq_hi <= 0;
		Voice_2_Pw_lo   <= 0;
		Voice_2_Pw_hi   <= 0;
		Voice_2_Control <= 0;
		Voice_2_Att_dec <= 0;
		Voice_2_Sus_Rel <= 0;
		Voice_3_Freq_lo <= 0;
		Voice_3_Freq_hi <= 0;
		Voice_3_Pw_lo   <= 0;
		Voice_3_Pw_hi   <= 0;
		Voice_3_Control <= 0;
		Voice_3_Att_dec <= 0;
		Voice_3_Sus_Rel <= 0;
		Filter_Fc_lo    <= 0;
		Filter_Fc_hi    <= 0;
		Filter_Res_Filt <= 0;
		Filter_Mode_Vol <= 0;
	end
	else begin
		if (we) begin
			last_wr <= data_in;
			case (addr)
				5'h00: Voice_1_Freq_lo <= data_in;
				5'h01: Voice_1_Freq_hi <= data_in;
				5'h02: Voice_1_Pw_lo   <= data_in;
				5'h03: Voice_1_Pw_hi   <= data_in[3:0];
				5'h04: Voice_1_Control <= data_in;
				5'h05: Voice_1_Att_dec <= data_in;
				5'h06: Voice_1_Sus_Rel <= data_in;
				5'h07: Voice_2_Freq_lo <= data_in;
				5'h08: Voice_2_Freq_hi <= data_in;
				5'h09: Voice_2_Pw_lo   <= data_in;
				5'h0a: Voice_2_Pw_hi   <= data_in[3:0];
				5'h0b: Voice_2_Control <= data_in;
				5'h0c: Voice_2_Att_dec <= data_in;
				5'h0d: Voice_2_Sus_Rel <= data_in;
				5'h0e: Voice_3_Freq_lo <= data_in;
				5'h0f: Voice_3_Freq_hi <= data_in;
				5'h10: Voice_3_Pw_lo   <= data_in;
				5'h11: Voice_3_Pw_hi   <= data_in[3:0];
				5'h12: Voice_3_Control <= data_in;
				5'h13: Voice_3_Att_dec <= data_in;
				5'h14: Voice_3_Sus_Rel <= data_in;
				5'h15: Filter_Fc_lo    <= data_in;
				5'h16: Filter_Fc_hi    <= data_in;
				5'h17: Filter_Res_Filt <= data_in;
				5'h18: Filter_Mode_Vol <= data_in;
			endcase
		end
		
		dac_mode <= ((Voice_1_Control & 8'hf9) == 8'h49 && (Voice_2_Control & 8'hf9) == 8'h49 && (Voice_3_Control & 8'hf9) == 8'h49);
	end
end

wire [17:0] dac_out;
sid8580_dac dac
(
	.clock(clk),
	.addr(Filter_Mode_Vol),
	.dout(dac_out)
);

assign audio_data = dac_mode ? dac_out : sound;

endmodule
