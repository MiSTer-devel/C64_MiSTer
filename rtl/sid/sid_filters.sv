
module sid_filters
#(
	parameter MULTI_FILTERS = 1
)
(
	input             clk,
	input             rst,
	input      [17:0] F0,
	input       [7:0] Res_Filt,
	input       [7:0] Mode_Vol,
	input      [17:0] voice1,
	input      [17:0] voice2,
	input      [17:0] voice3,
	input      [17:0] ext_in,
	input             input_valid,
	input             enable,
	output reg [17:0] sound,

	input             mode,
	input       [1:0] mixctl
);

reg signed [17:0] Vhp;
reg signed [17:0] Vbp;
reg signed [17:0] w0;
reg signed [17:0] q;

wire [10:0] divmul[16] =
'{
	1433, 1313, 1202, 1104, 1024, 938, 859, 788,
	 716,  656,  601,  552,  512, 469, 429, 394
};

wire [35:0] mul1 = w0 * Vhp;
wire [35:0] mul2 = w0 * Vbp;
wire [35:0] mul3 = q  * Vbp;

function [17:0] add_limit;
	input [17:0] a,b;
begin
	reg [18:0] tmp;
	tmp = {a[17],a} + {b[17],b};
	add_limit = ^tmp[18:17] ? {tmp[18], {17{tmp[17]}}} : tmp[17:0];
end
endfunction

function [17:0] sub_limit;
	input [17:0] a,b;
begin
	reg [18:0] tmp;
	tmp = {a[17],a} - {b[17],b};
	sub_limit = ^tmp[18:17] ? {tmp[18], {17{tmp[17]}}} : tmp[17:0];
end
endfunction

// Filter
always @(posedge clk) begin
	reg [17:0] dVbp;
	reg [17:0] Vlp;
	reg [17:0] dVlp;
	reg [17:0] Vi;
	reg [17:0] Vnf;
	reg [17:0] Vf;
	reg  [3:0] state;
	reg signed [35:0] mulr;
	reg signed [17:0] mula;
	reg signed [17:0] mulb;

	if (rst) begin
		state <= 0;
		Vlp   <= 0;
		Vbp   <= 0;
		Vhp   <= 0;
	end
	else begin
		state <= state + 1'd1;
		case (state)
			0:	if (input_valid) begin
					sound <= ^mulr[21:20] ? {mulr[21], {17{mulr[20]}}} : mulr[20:3];
					Vi    <= 0;
					Vnf   <= 16384;
					Vf    <= 0;
					w0    <= F0;
				end
				else begin
					state <= 0;
				end
			1:	begin
					if(Res_Filt[0])       Vi   <= add_limit(Vi,  voice1);
					else                  Vnf  <= add_limit(Vnf, voice1);
				end
			2:	begin
					if(Res_Filt[1])       Vi   <= add_limit(Vi,  voice2);
					else                  Vnf  <= add_limit(Vnf, voice2);
				end
			3:	begin
					if(Res_Filt[2])       Vi   <= add_limit(Vi,  voice3);
					else if(!Mode_Vol[7]) Vnf  <= add_limit(Vnf, voice3);

					                      dVbp <= {mul1[35], mul1[35:19]}; // w0 * Vhp
				end
			4:	begin
					if(Res_Filt[3])       Vi   <= add_limit(Vi,  ext_in);
					else                  Vnf  <= add_limit(Vnf, ext_in);

					                      dVlp <= {mul2[35], mul2[35:19]}; // w0 * Vbp
					                      Vbp  <= sub_limit(Vbp, dVbp);
					                      q    <= divmul[Res_Filt[7:4]];
				end
			5:	begin
					if(Mode_Vol[5])       Vf   <= add_limit(Vf, Vbp);

					                      Vlp  <= sub_limit(Vlp, dVlp);
				end
			6: begin
					if(Mode_Vol[4])       Vf   <= add_limit(Vf, Vlp);

					                      Vhp  <= sub_limit({mul3[35], mul3[26:10]}, Vlp); // q * Vbp
				end
			7: begin
					                      Vhp  <= sub_limit(Vhp, Vi);
				end
			8:	begin
					if(Mode_Vol[6])       Vf   <= add_limit(Vf, Vhp);
				end
			9:	begin
					mula  <= add_limit((mixctl[1] ? 18'd0 : Vnf), enable ? (mixctl[0] ? 18'd0 : mode ? Vf : (Vf - {Vf[17],Vf[17],Vf[17:2]})) : Vi);
					mulb  <= Mode_Vol[3:0];
				end
			10:begin
					mulr  <= mula * mulb;
					state <= 0;
				end
		endcase
	end
end

endmodule
