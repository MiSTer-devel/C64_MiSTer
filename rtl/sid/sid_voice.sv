
// altera message_off 10030
module sid_voice
(
	input         clock,
	input         ce_1m,
	input         reset,
	input         mode,
	input  [15:0] freq,
	input  [11:0] pw,
	input   [7:0] control,
	input   [7:0] att_dec,
	input   [7:0] sus_rel,
	input         osc_msb_in,

	input   [7:0] _st_out,
	input   [7:0] p_t_out,
	input   [7:0] ps__out,
	input   [7:0] pst_out,

	output [11:0] acc_ps,
	output [11:0] acc_t,
	
	output        osc_msb_out,
	output [13:0] voice_out,
	output [ 7:0] osc_out,
	output [ 7:0] env_out
);

// Internal Signals
reg  [23:0] oscillator;
reg         osc_edge;
reg         osc_msb_in_prv;
reg  [11:0] triangle;
reg  [11:0] sawtooth;
reg  [11:0] pulse;
reg  [11:0] noise;
reg  [22:0] lfsr_noise;
wire [ 7:0] envelope;
reg  [11:0] wave_out;
reg  [11:0] wave_out_r;
reg  [19:0] dca_out;

wire noise_ctrl    = control[7];
wire test_ctrl     = control[3];
wire ringmod_ctrl  = control[2];
wire sync_ctrl     = control[1];

// Signal Assignments
assign osc_msb_out = oscillator[23];
assign voice_out   = dca_out[19:6];
assign osc_out     = wave_out_r[11:4];
assign env_out     = envelope;

// Envelope Instantiation
sid_envelope adsr
(
	.clock(clock),
	.ce_1m(ce_1m),
	.reset(reset),
	.gate(control[0]),
	.att_dec(att_dec),
	.sus_rel(sus_rel),
	.envelope(envelope)
);

// Phase Accumulating Oscillator
always @(posedge clock) begin
	reg test_delay;

	if(ce_1m) begin
		osc_msb_in_prv <= osc_msb_in;
		test_delay <= mode & test_ctrl;
		
		if (reset || test_ctrl || test_delay || (sync_ctrl && ~osc_msb_in && osc_msb_in_prv))
			oscillator <= 0;
		else
			oscillator <= oscillator + freq;
	end
end

// Waveform Generator
always @(posedge clock) begin
	if (reset) begin
		triangle   <= 0;
		sawtooth   <= 0;
		pulse      <= 0;
		noise      <= 0;
		osc_edge   <= 0;
		lfsr_noise <= 23'h7fffff;
	end
	else if(ce_1m) begin
		triangle   <=	{12{(oscillator[23] ^ (ringmod_ctrl & ~osc_msb_in))}} ^ oscillator[22:11];

		sawtooth   <=	oscillator[23:12];

		pulse      <= 	test_ctrl ? 12'hfff :
							(oscillator[23:12] >= pw) ? 12'hfff : 12'h000;

		noise      <= 	{lfsr_noise[20], lfsr_noise[18], lfsr_noise[14],
							lfsr_noise[11], lfsr_noise[9], lfsr_noise[5],
							lfsr_noise[2], lfsr_noise[0], 4'b0000};

		osc_edge   <= 	oscillator[19];

		lfsr_noise <= 	test_ctrl ? 23'h7fffff :
							(oscillator[19] & ~osc_edge) ? {lfsr_noise[21:0], lfsr_noise[22] ^ lfsr_noise[17]} :
							lfsr_noise;
    end
end

assign acc_ps = oscillator[23:12];
assign acc_t  = {oscillator[23] ^ (ringmod_ctrl & ~osc_msb_in), oscillator[22:12]};

// Waveform Output Selector
always @(*) begin
	case (control[6:4])
		3'b000: wave_out = 0;
		3'b001: wave_out = triangle;
		3'b010: wave_out = sawtooth;
		3'b011: wave_out = {_st_out, 4'b0000};
		3'b100: wave_out = pulse;
		3'b101: wave_out = {p_t_out, 4'b0000} & pulse;
		3'b110: wave_out = {ps__out, 4'b0000} & pulse;
		3'b111: wave_out = {pst_out, 4'b0000} & pulse;
	endcase
	if (noise_ctrl) wave_out = control[6:4] ? (wave_out & noise) : noise;
end

// for OSC3 readback
always @(posedge clock) if(ce_1m) wave_out_r <= wave_out;

// DAC with floating input simulation
always @(posedge clock) begin
	reg [16:0] keep_cnt;
	reg [11:0] dac_out;

	if(ce_1m) begin
		if(keep_cnt) keep_cnt <= keep_cnt - 1'd1;
		else dac_out <= 0;

		if(control[7:4]) begin
			keep_cnt <= 'h14000;
			dac_out  <= wave_out;
		end

		dca_out <= $signed({~dac_out[11], dac_out[10:0]}) * $signed({1'b0, envelope});
	end
end

endmodule
