
module sid_envelope
(
	input            clock,
	input            ce_1m,

	input            reset,
	input            gate,
	input     [ 7:0] att_dec,
	input     [ 7:0] sus_rel,

	output reg [7:0] envelope
);

localparam ST_RELEASE  = 0;
localparam ST_ATTACK   = 1;
localparam ST_DEC_SUS  = 2;

reg  [1:0] state;

wire [14:0] rates[16] = 
'{
      8,  //   2ms*1.0MHz/256 =     7.81
     31,  //   8ms*1.0MHz/256 =    31.25
     62,  //  16ms*1.0MHz/256 =    62.50
     94,  //  24ms*1.0MHz/256 =    93.75
    148,  //  38ms*1.0MHz/256 =   148.44
    219,  //  56ms*1.0MHz/256 =   218.75
    266,  //  68ms*1.0MHz/256 =   265.63
    312,  //  80ms*1.0MHz/256 =   312.50
    391,  // 100ms*1.0MHz/256 =   390.63
    976,  // 250ms*1.0MHz/256 =   976.56
   1953,  // 500ms*1.0MHz/256 =  1953.13
   3125,  // 800ms*1.0MHz/256 =  3125.00
   3906,  //   1 s*1.0MHz/256 =  3906.25
  11719,  //   3 s*1.0MHz/256 = 11718.75
  19531,  //   5 s*1.0MHz/256 = 19531.25
  31250   //   8 s*1.0MHz/256 = 31250.00 
};

wire [14:0] rate_period = rates[(state == ST_ATTACK) ? att_dec[7:4] : (state == ST_DEC_SUS) ? att_dec[3:0] : sus_rel[3:0]];

always @(posedge clock) begin
	reg        hold_zero;
	reg  [4:0] exponential_counter_period;
	reg        gate_edge;
	reg [14:0] rate_counter;
	reg  [4:0] exponential_counter;

	case(envelope)
		'hff: exponential_counter_period <= 0;
		'h5d: exponential_counter_period <= 1;
		'h36: exponential_counter_period <= 3;
		'h1a: exponential_counter_period <= 7;
		'h0e: exponential_counter_period <= 15;
		'h06: exponential_counter_period <= 29;
		'h00: exponential_counter_period <= 0;
	endcase;

	if (reset) begin
		state <= ST_RELEASE;
		gate_edge <= gate;
		envelope  <= 0;
		hold_zero <= 1;
		exponential_counter <= 0;
		exponential_counter_period <= 0;
		rate_counter <= 0;
	end
	else if(ce_1m) begin

		rate_counter <= rate_counter + 1'd1;
		if(rate_counter == rate_period) begin
			rate_counter <= 0;

			exponential_counter <= exponential_counter + 1'b1;
			if (state == ST_ATTACK || exponential_counter == exponential_counter_period) begin
				exponential_counter <= 0;

				case (state)
					 ST_ATTACK: begin
							envelope <= envelope + 1'b1;
							if (envelope == 8'hfe) state <= ST_DEC_SUS;
						end

					ST_DEC_SUS: begin
							if(envelope != {2{sus_rel[7:4]}} && !hold_zero) begin
								envelope <= envelope - 1'b1;
							end
						end
						
					ST_RELEASE: begin
							if(!hold_zero) envelope <= envelope - 1'b1;
						end
				endcase
				
				if(state != ST_ATTACK && envelope == 1) hold_zero <= 1;
			end
		end

		gate_edge <= gate;
		if (~gate_edge & gate) begin
			state <= ST_ATTACK;
			hold_zero <= 0;
		end
		if (gate_edge & ~gate) state <= ST_RELEASE;
	end
end

endmodule
