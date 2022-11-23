// ----------------------------------------------------------------------------
// SID filter
// Copyright (C) 2022 Alexey Melnikov
//
// This file is based on filter from reDIP-SID.
// Copyright (C) 2022  Dag Lem <resid@nimrod.no>
//
// This source describes Open Hardware and is licensed under the CERN-OHL-S v2.
//
// You may redistribute and modify this source and make products using it under
// the terms of the CERN-OHL-S v2 (https://ohwr.org/cern_ohl_s_v2.txt).
//
// This source is distributed WITHOUT ANY EXPRESS OR IMPLIED WARRANTY,
// INCLUDING OF MERCHANTABILITY, SATISFACTORY QUALITY AND FITNESS FOR A
// PARTICULAR PURPOSE. Please see the CERN-OHL-S v2 for applicable conditions.
//
// Source location: https://github.com/daglem/reDIP-SID
// ----------------------------------------------------------------------------

module sid_filter
(
	input               clk,
	input         [2:0] state,
	input               mode,

	input        [15:0] F0,
	input         [7:0] Res_Filt,
	input         [7:0] Mode_Vol,
	input signed [21:0] voice1,
	input signed [21:0] voice2,
	input signed [21:0] voice3,
	input signed [21:0] ext_in,

	output       [17:0] audio
);

localparam signed [23:0] MIXER_DC_6581 = 24'((-1 << 20)/18);

// Clamp to 16 bits.
function signed [15:0] clamp(wire signed [16:0] x);
	clamp = ^x[16:15] ? {x[16], {15{x[15]}}} : x[15:0];
endfunction

wire [10:0] _1_Q_lsl10_tbl[32] =
'{
	1448, 1324, 1219, 1129, 1052, 984, 925, 872, 826, 783, 745, 711, 679, 651, 624, 600,
	1448, 1328, 1218, 1117, 1024, 939, 861, 790, 724, 664, 609, 558, 512, 470, 431, 395
};

// o = c +- (a * b)
reg signed  [31:0] c;
reg                s;
reg signed  [15:0] a;
reg signed  [15:0] b;
wire signed [31:0] m = a * b;
wire signed [31:0] o = s ? (c - m) : (c + m);

// Filter states for two SID chips, updated as follows:
// vlp = vlp - w0*vbp
// vbp = vbp - w0*vhp
// vhp = 1/Q*vbp - vlp - vi
reg signed [15:0] vlp, vlp2, vlp_next;
reg signed [15:0] vbp, vbp2, vbp_next;
reg signed [15:0] vhp, vhp2, vhp_next;
reg signed [16:0] dv;

always_comb begin
	// Intermediate results for filter.
	// Shifts -w0*vbp and -w0*vlp right by 17.
	dv       = 17'(o >>> 17);
	vlp_next = clamp(vlp + dv);
	vbp_next = clamp(vbp + dv);
	vhp_next = clamp(o[10 +: 17]);
end


// Filter
always @(posedge clk) begin
	reg [10:0] _1_Q_lsl10;

	reg signed [15:0] vi = 0;
	reg signed [15:0] vd = 0;

	case (state)
		2:	begin
				// MOS6581: 1/Q =~ ~res/8 (not used - op-amps are not ideal)
				// MOS8580: 1/Q =~ 2^((4 - res)/8)
				_1_Q_lsl10 <= _1_Q_lsl10_tbl[{mode, Res_Filt[7:4]}];

				// Mux for filter path.
				// Each voice is 22 bits, i.e. the sum of four voices is 24 bits.
				vi <= 16'(((Res_Filt[0] ? 24'(voice1) : '0) +
							  (Res_Filt[1] ? 24'(voice2) : '0) +
							  (Res_Filt[2] ? 24'(voice3) : '0) +
							  (Res_Filt[3] ? 24'(ext_in) : '0)) >>> 7);

				// Mux for direct audio path.
				// 3 OFF (Mode_Vol[7]) disconnects voice 3 from the direct audio path.
				// We add in the mixer DC here, to save time in calculation of
				// the final audio sum.
				vd <= 16'(((mode        ? '0 : MIXER_DC_6581) +
							  (Res_Filt[0] ? '0 : 24'(voice1)) +
							  (Res_Filt[1] ? '0 : 24'(voice2)) +
							  (Res_Filt[2] |
							   Mode_Vol[7] ? '0 : 24'(voice3)) +
							  (Res_Filt[3] ? '0 : 24'(ext_in))) >>> 7);

				// vlp = vlp - w0*vbp
				// We first calculate -w0*vbp
				c <= 0;
				s <= 1;
				a <= F0;   // w0*T << 17
				b <= vbp;  // vbp
			end
		3:	begin
				// Result for vlp ready. See calculation of vlp_next above.
				{ vlp, vlp2 } <= { vlp2, vlp_next };

				// vbp = vbp - w0*vhp
				// We first calculate -w0*vhp
				c <= 0;
				s <= 1;
				// a <= a; // w0*T << 17
				b <= vhp;  // vhp
			end
		4:	begin
				// Result for vbp ready. See calculation of vbp_next above.
				{ vbp, vbp2 } <= { vbp2, vbp_next };

				// vhp = 1/Q*vbp - vlp - vi
				c <= -(32'(vlp2) + 32'(vi)) << 10;
				s <= 0;
				a <= _1_Q_lsl10; // 1/Q << 10
				b <= vbp_next;   // vbp
			end
		5: begin
				// Result for vbp ready. See calculation of vhp_next above.
				{ vhp, vhp2 } <= { vhp2, vhp_next };

				// Audio output: aout = vol*amix
				// In the real SID, the signal is inverted first in the mixer
				// op-amp, and then again in the volume control op-amp.
				c <= 0;
				s <= 0;
				a <= {12'b0, Mode_Vol[3:0]}; // Master volume
				b <= clamp(17'(vd) +         // Audio mixer / master volume input
						(Mode_Vol[4] ? 17'(vlp2)     : '0) +
						(Mode_Vol[5] ? 17'(vbp2)     : '0) +
						(Mode_Vol[6] ? 17'(vhp_next) : '0));
			end
	endcase
end

assign audio = o[19:2];

endmodule
