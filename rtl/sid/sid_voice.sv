
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

	output [11:0] acc_t,
	
	output        osc_msb_out,
	output [21:0] voice_out,
	output [ 7:0] osc_out,
	output [ 7:0] env_out
);

// Internal Signals
reg  [23:0] oscillator;
reg         osc_edge;
reg         osc_msb_in_prv;
reg  [11:0] saw_tri;
reg         pulse;
reg  [11:0] noise;
reg  [22:0] lfsr_noise;
wire [ 7:0] envelope;
reg  [11:0] wave_out_r;
reg signed [21:0] dca_out;

wire test_ctrl     = control[3];
wire ringmod_ctrl  = control[2];
wire sync_ctrl     = control[1];

// Signal Assignments
assign osc_msb_out = oscillator[23];
assign voice_out   = dca_out;
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
		oscillator <= (reset || test_ctrl || test_delay || (sync_ctrl && ~osc_msb_in && osc_msb_in_prv)) ? 24'd0 : (oscillator + freq);
	end
end

assign acc_t = {oscillator[23], oscillator[22:12] ^ {11{~control[5] & ((ringmod_ctrl & ~osc_msb_in) ^ oscillator[23])}}};

// Waveform Generator
always @(posedge clock) begin
	if (reset) begin
		saw_tri    <= 0;
		pulse      <= 0;
		noise      <= 0;
		osc_edge   <= 0;
		lfsr_noise <= 23'h7fffff;
	end
	else if(ce_1m) begin
		saw_tri    <= acc_t;
		pulse      <= (test_ctrl || (oscillator[23:12] >= pw));
		noise      <= {lfsr_noise[20], lfsr_noise[18], lfsr_noise[14], lfsr_noise[11], lfsr_noise[9], lfsr_noise[5], lfsr_noise[2], lfsr_noise[0], 4'b0000};
		osc_edge   <= oscillator[19];
		lfsr_noise <= (oscillator[19] & ~osc_edge) ? {lfsr_noise[21:0], (reset | test_ctrl | lfsr_noise[22]) ^ lfsr_noise[17]} : lfsr_noise;
    end
end

reg  [11:0] norm;
reg   [7:0] comb;

// Waveform Output Selector
always_comb begin
	case (control[7:4])
		4'b0001: norm = {saw_tri[10:0],1'b0};
		4'b0010: norm = saw_tri;
		4'b0100: norm = {12{pulse}};
		4'b1000: norm = noise;
		default: norm = 0;
	endcase
		
	case (control[7:4])
		4'b0011: comb = _st_out; 
		4'b0101: comb = p_t_out & {8{pulse}};
		4'b0110: comb = ps__out & {8{pulse}};
		4'b0111: comb = pst_out & {8{pulse}};
		default: comb = 0;
	endcase
end

wire [11:0] norm_6581;
sid_dac #(.BITS (12)) waveform_dac
(
  .vin  (norm),
  .vout (norm_6581)
);

reg [11:0] norm_dac;
always @(posedge clock) norm_dac <= mode ? norm : norm_6581;

wire [11:0] wave_out = norm_dac | {comb, 4'b0000};

wire [7:0] env_6581;
sid_dac #(.BITS (8)) envelope_dac
(
  .vin  (envelope),
  .vout (env_6581)
);

reg [7:0] env_dac;
always @(posedge clock) env_dac <= mode ? envelope : env_6581;


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

		dca_out <= $signed({~dac_out[11], dac_out[10:0]}) * $signed({1'b0, env_dac});
	end
end

endmodule
