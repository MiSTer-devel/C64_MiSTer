
module sid_top 
#(
	parameter MULTI_FILTERS = 1, 
	parameter USE_8580_TABLES = 1,
	parameter DUAL = 1
)
(
	input         reset,

	input         clk,
	input         ce_1m,

	input [N-1:0] cs,       // not used if DUAL is 0
	input         we,
	input   [4:0] addr,
	input   [7:0] data_in,
	output  [7:0] data_out,

	input   [7:0] pot_x_l,
	input   [7:0] pot_y_l,
	input  [13:0] ext_in_l,
	output [17:0] audio_l,

	input   [7:0] pot_x_r,  // not used if DUAL is 0
	input   [7:0] pot_y_r,  // not used if DUAL is 0
	input  [13:0] ext_in_r, // not used if DUAL is 0
	output [17:0] audio_r,

	input [N-1:0] filter_en,
	input [N-1:0] mode,
	input [(N*2)-1:0] cfg,

	input         ld_clk,
	input  [11:0] ld_addr,
	input  [15:0] ld_data,
	input         ld_wr
);

localparam N = DUAL ? 2 : 1;

// Internal Signals
reg  [15:0] Voice_1_Freq[N];
reg  [11:0] Voice_1_Pw[N];
reg   [7:0] Voice_1_Control[N];
reg   [7:0] Voice_1_Att_dec[N];
reg   [7:0] Voice_1_Sus_Rel[N];

reg  [15:0] Voice_2_Freq[N];
reg  [11:0] Voice_2_Pw[N];
reg   [7:0] Voice_2_Control[N];
reg   [7:0] Voice_2_Att_dec[N];
reg   [7:0] Voice_2_Sus_Rel[N];

reg  [15:0] Voice_3_Freq[N];
reg  [11:0] Voice_3_Pw[N];
reg   [7:0] Voice_3_Control[N];
reg   [7:0] Voice_3_Att_dec[N];
reg   [7:0] Voice_3_Sus_Rel[N];

reg  [10:0] Filter_Fc[N];
reg   [7:0] Filter_Res_Filt[N];
reg   [7:0] Filter_Mode_Vol[N];

wire  [7:0] Misc_Osc3[N];
wire  [7:0] Misc_Env3[N];

wire [13:0] voice_1[N];
wire [13:0] voice_2[N];
wire [13:0] voice_3[N];

wire        voice_1_PA_MSB[N];
wire        voice_2_PA_MSB[N];
wire        voice_3_PA_MSB[N];

wire  [7:0] _st_out[N*3];
wire  [7:0] p_t_out[N*3];
wire  [7:0] ps__out[N*3];
wire  [7:0] pst_out[N*3];
wire [11:0] acc_ps[N*3];
wire [11:0] acc_t[N*3];

wire [17:0] sound[N];

reg         dac_mode[N];
reg   [7:0] last_wr[N];

generate
	genvar i;
	
	for(i=0; i<N; i=i+1) begin :chip
		sid_voice v1
		(
			.clock(clk),
			.ce_1m(ce_1m),
			.reset(reset),
			.mode(mode[i]),
			.freq(Voice_1_Freq[i]),
			.pw(Voice_1_Pw[i]),
			.control(Voice_1_Control[i]),
			.att_dec(Voice_1_Att_dec[i]),
			.sus_rel(Voice_1_Sus_Rel[i]),
			.osc_msb_in(voice_3_PA_MSB[i]),
			.osc_msb_out(voice_1_PA_MSB[i]),
			.voice_out(voice_1[i]),
			._st_out(_st_out[i*3+0]),
			.p_t_out(p_t_out[i*3+0]),
			.ps__out(ps__out[i*3+0]),
			.pst_out(pst_out[i*3+0]),
			.acc_ps(acc_ps[i*3+0]),
			.acc_t(acc_t[i*3+0])
		);

		sid_voice v2
		(
			.clock(clk),
			.ce_1m(ce_1m),
			.reset(reset),
			.mode(mode[i]),
			.freq(Voice_2_Freq[i]),
			.pw(Voice_2_Pw[i]),
			.control(Voice_2_Control[i]),
			.att_dec(Voice_2_Att_dec[i]),
			.sus_rel(Voice_2_Sus_Rel[i]),
			.osc_msb_in(voice_1_PA_MSB[i]),
			.osc_msb_out(voice_2_PA_MSB[i]),
			.voice_out(voice_2[i]),
			._st_out(_st_out[i*3+1]),
			.p_t_out(p_t_out[i*3+1]),
			.ps__out(ps__out[i*3+1]),
			.pst_out(pst_out[i*3+1]),
			.acc_ps(acc_ps[i*3+1]),
			.acc_t(acc_t[i*3+1])
		);

		sid_voice v3
		(
			.clock(clk),
			.ce_1m(ce_1m),
			.reset(reset),
			.mode(mode[i]),
			.freq(Voice_3_Freq[i]),
			.pw(Voice_3_Pw[i]),
			.control(Voice_3_Control[i]),
			.att_dec(Voice_3_Att_dec[i]),
			.sus_rel(Voice_3_Sus_Rel[i]),
			.osc_msb_in(voice_2_PA_MSB[i]),
			.osc_msb_out(voice_3_PA_MSB[i]),
			.voice_out(voice_3[i]),
			.osc_out(Misc_Osc3[i]),
			.env_out(Misc_Env3[i]),
			._st_out(_st_out[i*3+2]),
			.p_t_out(p_t_out[i*3+2]),
			.ps__out(ps__out[i*3+2]),
			.pst_out(pst_out[i*3+2]),
			.acc_ps(acc_ps[i*3+2]),
			.acc_t(acc_t[i*3+2])
		);
		
		sid_filters #(MULTI_FILTERS) filters
		(
			.clk(clk),
			.rst(reset),
			.F0(F0[i]),
			.Res_Filt(Filter_Res_Filt[i]),
			.Mode_Vol(Filter_Mode_Vol[i]),
			.voice1({{4{voice_1[i][13]}},voice_1[i]}),
			.voice2({{4{voice_2[i][13]}},voice_2[i]}),
			.voice3({{4{voice_3[i][13]}},voice_3[i]}),
			.ext_in(i ? {{4{ext_in_r[13]}},ext_in_r} : {{4{ext_in_l[13]}},ext_in_l}),
			.input_valid(ce_1m),
			.sound(sound[i]),
			.enable(filter_en[i]),
			.mode(mode[i])
		);
		
		// Register Decoding
		always @(posedge clk) begin
			if (reset) begin
				Voice_1_Freq[i]    <= 0;
				Voice_1_Pw[i]      <= 0;
				Voice_1_Control[i] <= 0;
				Voice_1_Att_dec[i] <= 0;
				Voice_1_Sus_Rel[i] <= 0;
				Voice_2_Freq[i]    <= 0;
				Voice_2_Pw[i]      <= 0;
				Voice_2_Control[i] <= 0;
				Voice_2_Att_dec[i] <= 0;
				Voice_2_Sus_Rel[i] <= 0;
				Voice_3_Freq[i]    <= 0;
				Voice_3_Pw[i]      <= 0;
				Voice_3_Control[i] <= 0;
				Voice_3_Att_dec[i] <= 0;
				Voice_3_Sus_Rel[i] <= 0;
				Filter_Fc[i]       <= 0;
				Filter_Res_Filt[i] <= 0;
				Filter_Mode_Vol[i] <= 0;
			end
			else begin
				if (we && (!DUAL || cs[i])) begin
					last_wr[i] <= data_in;
					case (addr)
						5'h00: Voice_1_Freq[i][7:0] <= data_in;
						5'h01: Voice_1_Freq[i][15:8]<= data_in;
						5'h02: Voice_1_Pw[i][7:0]   <= data_in;
						5'h03: Voice_1_Pw[i][11:8]  <= data_in[3:0];
						5'h04: Voice_1_Control[i]   <= data_in;
						5'h05: Voice_1_Att_dec[i]   <= data_in;
						5'h06: Voice_1_Sus_Rel[i]   <= data_in;
						5'h07: Voice_2_Freq[i][7:0] <= data_in;
						5'h08: Voice_2_Freq[i][15:8]<= data_in;
						5'h09: Voice_2_Pw[i][7:0]   <= data_in;
						5'h0a: Voice_2_Pw[i][11:8]  <= data_in[3:0];
						5'h0b: Voice_2_Control[i]   <= data_in;
						5'h0c: Voice_2_Att_dec[i]   <= data_in;
						5'h0d: Voice_2_Sus_Rel[i]   <= data_in;
						5'h0e: Voice_3_Freq[i][7:0] <= data_in;
						5'h0f: Voice_3_Freq[i][15:8]<= data_in;
						5'h10: Voice_3_Pw[i][7:0]   <= data_in;
						5'h11: Voice_3_Pw[i][11:8]  <= data_in[3:0];
						5'h12: Voice_3_Control[i]   <= data_in;
						5'h13: Voice_3_Att_dec[i]   <= data_in;
						5'h14: Voice_3_Sus_Rel[i]   <= data_in;
						5'h15: Filter_Fc[i][2:0]    <= data_in[2:0];
						5'h16: Filter_Fc[i][10:3]   <= data_in;
						5'h17: Filter_Res_Filt[i]   <= data_in;
						5'h18: Filter_Mode_Vol[i]   <= data_in;
					endcase
				end
				
				dac_mode[i] <= ((Voice_1_Control[i] & 8'hf9) == 8'h49 && (Voice_2_Control[i] & 8'hf9) == 8'h49 && (Voice_3_Control[i] & 8'hf9) == 8'h49);
			end
		end
	end
endgenerate

reg  [17:0] F0[N];
reg  [10:0] Fc;
reg   [1:0] cfg_i;
reg         mode_i;
reg   [7:0] dac_addr;
reg  [17:0] dac_out[N];

wire [17:0] f0;
wire [17:0] dac_o;

sid_tables #(USE_8580_TABLES,MULTI_FILTERS) sid_tables
(
	.clock(clk),
	.mode(mode_i),

	.acc_ps(f_acc_ps),
	.acc_t(f_acc_t),
	._st_out(f__st_out),
	.p_t_out(f_p_t_out),
	.ps__out(f_ps__out),
	.pst_out(f_pst_out),
	
	.cfg(cfg_i),
	.Fc(Fc),
	.F0(f0),
	.ld_clk(ld_clk),
	.ld_addr(ld_addr),
	.ld_data(ld_data),
	.ld_wr(ld_wr),
	
	.dac_addr(dac_addr),
	.dac_dout(dac_o)
);

wire  [7:0] f__st_out;
wire  [7:0] f_p_t_out;
wire  [7:0] f_ps__out;
wire  [7:0] f_pst_out;
reg  [11:0] f_acc_ps;
reg  [11:0] f_acc_t;

always @(posedge clk) begin
	reg [3:0] state;
	reg [17:0] dac_t;
	
	if(~&state) state <= state + 1'd1;
	if(ce_1m) state <= 0;

	case(state)
		1,7: mode_i <= DUAL ? mode[state[2]] : mode[0];
	endcase

	case(state)
		1,3,5,7,9,11: begin
			f_acc_ps <= acc_ps[state[3:1]];
			f_acc_t  <= acc_t[state[3:1]];
		end
	endcase

	case(state)
		3,5,7: begin
			_st_out[state[3:1]-1'd1] <= f__st_out;
			p_t_out[state[3:1]-1'd1] <= f_p_t_out;
			ps__out[state[3:1]-1'd1] <= f_ps__out;
			pst_out[state[3:1]-1'd1] <= f_pst_out;
		end
		9,11,13: if(DUAL) begin
			_st_out[state[3:1]-1'd1] <= f__st_out;
			p_t_out[state[3:1]-1'd1] <= f_p_t_out;
			ps__out[state[3:1]-1'd1] <= f_ps__out;
			pst_out[state[3:1]-1'd1] <= f_pst_out;
		end
	endcase
	
	case(state)
		1,7: begin Fc <= Filter_Fc[state[2]]; cfg_i <= cfg[state[2]*2 +:2]; end
		  6: begin F0[0] <= f0; end
		 12: if(DUAL) F0[1] <= f0;
	endcase

	case(state)
		1,7: begin dac_addr <= Filter_Mode_Vol[state[2]]; end
		  6: dac_t <= dac_o;
		 12: begin dac_out[0] <= dac_t; if(DUAL) dac_out[1] <= dac_o; end
	endcase
end

always_comb begin
	case (addr)
		  5'h19: data_out = (!DUAL || cs[0]) ? pot_x_l : pot_x_r;
		  5'h1a: data_out = (!DUAL || cs[0]) ? pot_y_l : pot_y_r;
		  5'h1b: data_out = Misc_Osc3[|DUAL & ~cs[0]];
		  5'h1c: data_out = Misc_Env3[|DUAL & ~cs[0]];
		default: data_out = last_wr[|DUAL & ~cs[0]];
	endcase
end

assign audio_l = dac_mode[0] ? dac_out[0] : sound[0];
assign audio_r = (!DUAL) ? audio_l : dac_mode[1] ? dac_out[1] : sound[1];

endmodule
