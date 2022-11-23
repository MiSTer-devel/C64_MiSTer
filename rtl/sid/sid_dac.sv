// ----------------------------------------------------------------------------
// This file is part of reDIP SID, a MOS 6581/8580 SID FPGA emulation platform.
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

// ----------------------------------------------------------------------------
// This file is based on documentation and code from reSID, see
// https://github.com/daglem/reSID
//
// The SID DACs are built up as follows:
//
//          n  n-1      2   1   0    VGND
//          |   |       |   |   |      |   Termination
//         2R  2R      2R  2R  2R     2R   only for
//          |   |       |   |   |      |   MOS 8580
//      Vo  --R---R--...--R---R--    ---
//
//
// All MOS 6581 DACs are missing a termination resistor at bit 0. This causes
// pronounced errors for the lower 4 - 5 bits (e.g. the output for bit 0 is
// actually equal to the output for bit 1), resulting in DAC discontinuities
// for the lower bits.
// In addition to this, the 6581 DACs exhibit further severe discontinuities
// for higher bits, which may be explained by a less than perfect match between
// the R and 2R resistors, or by output impedance in the NMOS transistors
// providing the bit voltages. A good approximation of the actual DAC output is
// achieved for 2R/R ~ 2.20.
//
// The MOS 8580 DACs, on the other hand, do not exhibit any discontinuities.
// These DACs include the correct termination resistor, and also seem to have
// very accurately matched R and 2R resistors (2R/R = 2.00).
// ----------------------------------------------------------------------------

`default_nettype none

module sid_dac #(
    parameter  BITS       = 12,
    parameter  _2R_DIV_R  = 2.20,
    parameter  TERM       = 0
)(
    input  logic [BITS-1:0] vin,
    output logic [BITS-1:0] vout
);
    localparam SCALEBITS  = 4;
    localparam MSB        = BITS+SCALEBITS-1;

    logic [MSB:0] bitval[BITS];

    logic [MSB:0] bitsum[BITS];
	 logic [BITS-1:0] bit1 = 1;

	 generate 
		 // Sum values for all set bits, adding 0.5 for rounding by truncation.
		 /* verilator lint_off ALWCOMBORDER */
		 genvar i;
		 for (i = 0; i < BITS; i++) begin :init
			  always_comb begin
					bitsum[i] =
						 (i == 0 ? bit1 << (SCALEBITS - 1) : bitsum[i-1]) +
						 (vin[i] ? bitval[i] : 1'd0);
			  end
		 end
		 /* verilator lint_on ALWCOMBORDER */
	 endgenerate

    always_comb begin
        vout = bitsum[BITS-1][MSB-:BITS];
    end

    initial begin
        if (_2R_DIV_R == 2.20 && TERM == 0 && SCALEBITS == 4) begin
            case (BITS)
              12: begin
							//$readmemh("dac_6581_waveform.hex", bitval);
							bitval[0]  = 'h21;
							bitval[1]  = 'h30;
							bitval[2]  = 'h55;
							bitval[3]  = 'ha0;
							bitval[4]  = 'h135;
							bitval[5]  = 'h256;
							bitval[6]  = 'h486;
							bitval[7]  = 'h8c6;
							bitval[8]  = 'h1102;
							bitval[9]  = 'h20f8;
							bitval[10] = 'h3fec;
							bitval[11] = 'h7bed;
						end
               8: begin
							//$readmemh("dac_6581_envelope.hex", bitval);
							bitval[0]  = 'h1d;
							bitval[1]  = 'h2a;
							bitval[2]  = 'h4b;
							bitval[3]  = 'h8d;
							bitval[4]  = 'h110;
							bitval[5]  = 'h20e;
							bitval[6]  = 'h3fb;
							bitval[7]  = 'h7b8;
						end
            endcase
        end
    end
endmodule
