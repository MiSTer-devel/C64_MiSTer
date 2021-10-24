// MOS8520
// based on MOS6526 by Rayne
// Timers & Interrupts are rewritten by slingshot
// Passes all Lorenz CIA Timer tests
// Passes all CIA tests from VICE, except dd0dtest
//
// 8520 version by Sorgelig

module iecdrv_mos8520 (
  input  wire       clk,
  input  wire       phi2_p, // Phi 2 positive edge
  input  wire       phi2_n, // Phi 2 negative edge
  input  wire       res_n,
  input  wire       cs_n,
  input  wire       rw,

  input  wire [3:0] rs,
  input  wire [7:0] db_in,
  output reg  [7:0] db_out,

  input  wire [7:0] pa_in,
  output reg  [7:0] pa_out,
  input  wire [7:0] pb_in,
  output reg  [7:0] pb_out,

  input  wire       flag_n,
  output reg        pc_n,

  input  wire       tod,

  input  wire       sp_in,
  output reg        sp_out,

  input  wire       cnt_in,
  output reg        cnt_out,

  output reg        irq_n
);

// Internal Registers
reg [7:0] pra;
reg [7:0] prb;
reg [7:0] ddra;
reg [7:0] ddrb;

reg [7:0] ta_lo;
reg [7:0] ta_hi;
reg [7:0] tb_lo;
reg [7:0] tb_hi;

reg [7:0] sdr;
reg [4:0] imr;
reg [4:0] icr;
reg timer_b_int; // for Timer B bug
reg [7:0] cra;
reg [7:0] crb;

// Internal Signals
reg [15:0] timer_a;
reg [15:0] timer_b;

reg [23:0] tod_count;
reg        tod_prev;
reg        tod_run;
reg [23:0] tod_alarm;
reg        tod_alarm_reg;
reg [23:0] tod_latch;
reg        tod_latched;

reg        sp_pending;
reg        sp_transmit;
reg [ 7:0] sp_shiftreg;
reg        icr3;

reg        cnt_in_prev;
reg        cnt_out_r;
reg [ 2:0] cnt_pulsecnt;

reg        int_reset;

wire       rd = phi2_n & !cs_n & rw;
wire       wr = phi2_n & !cs_n & !rw;

// Register Decoding
always @(posedge clk) begin
  if (!res_n) db_out <= 8'h00;
  else if (rd)
    case (rs)
      4'h0: db_out <= pa_in;
      4'h1: db_out <= pb_in;
      4'h2: db_out <= ddra;
      4'h3: db_out <= ddrb;
      4'h4: db_out <= timer_a[ 7:0];
      4'h5: db_out <= timer_a[15:8];
      4'h6: db_out <= timer_b[ 7:0];
      4'h7: db_out <= timer_b[15:8];
      4'h8: db_out <= tod_latch[7:0];
      4'h9: db_out <= tod_latch[15:8];
      4'ha: db_out <= tod_latch[23:16];
      4'hb: db_out <= 8'h00;
      4'hc: db_out <= sdr;
      4'hd: db_out <= {~irq_n, 2'b00, icr};
      4'he: db_out <= {1'b0, cra[6:5], 1'b0, cra[3:0]};
      4'hf: db_out <= {crb[7:5], 1'b0, crb[3:0]};
    endcase
end

// Port A Output
always @(posedge clk) begin
  if (!res_n) begin
    pra  <= 8'h00;
    ddra <= 8'h00;
  end
  else if (wr)
    case (rs)
      4'h0: pra  <= db_in;
      4'h2: ddra <= db_in;
      default: ;
    endcase
  if (phi2_p) pa_out <= pra | ~ddra;
end

// Port B Output
always @(posedge clk) begin
  if (!res_n) begin
    prb  <= 8'h00;
    ddrb <= 8'h00;
  end
  else if (wr)
    case (rs)
      4'h1: prb  <= db_in;
      4'h3: ddrb <= db_in;
      default: ;
    endcase
  if (phi2_p) begin
    pb_out[7]   <= crb[1] ? (crb[2] ? timerBff ^ timerBoverflow : timerBoverflow) : prb[7] | ~ddrb[7];
    pb_out[6]   <= cra[1] ? (cra[2] ? timerAff ^ timerAoverflow : timerAoverflow) : prb[6] | ~ddrb[6];
    pb_out[5:0] <= prb[5:0] | ~ddrb[5:0];
  end
end

// FLAG Input
always @(posedge clk) begin
	reg old_flag, flag;

	old_flag <= flag_n;
	if(old_flag & ~flag_n) flag <= 1'b1;
  
	if (!res_n) begin
		icr[4] <= 1'b0;
		flag <= 1'b0;
	end
	else begin
		if (phi2_p) begin
			if (int_reset) icr[4] <= 1'b0;
			if ((old_flag & ~flag_n) | flag) begin
				icr[4] <= 1'b1;
				flag <= 1'b0;
			end
		end
	end
end

// Port Control Output
reg pcr;
always @(posedge clk) begin
  if (!cs_n && rs == 4'h1) pcr <= 1'b0;
  if (phi2_p) begin
	 pc_n <= pcr;
	 pcr  <= 1'b1;
  end
end

// Timer A
reg countA0, countA1, countA2, countA3, loadA1, oneShotA0;
reg timerAff;
wire timerAin = cra[5] ? countA1 : 1'b1;
wire [15:0] newTimerAVal = countA3 ? (timer_a - 1'b1) : timer_a;
wire timerAoverflow = !newTimerAVal & countA2;

always @(posedge clk) begin

  if (!res_n) begin
    ta_lo          <= 8'hff;
    ta_hi          <= 8'hff;
    cra            <= 8'h00;
    timer_a        <= 16'h0000;
    timerAff       <= 1'b0;
    icr[0]         <= 1'b0;
  end
  else begin
    if (phi2_p) begin
      if (int_reset) icr[0] <= 0;
      countA0 <= cnt_in && ~cnt_in_prev;
      countA1 <= countA0;
      countA2 <= timerAin & cra[0];
      countA3 <= countA2;
      loadA1 <= cra[4];
      cra[4] <= 0;
      oneShotA0 <= cra[3];
      timer_a <= newTimerAVal;
      if (timerAoverflow) begin
        timerAff <= ~timerAff;
        icr[0] <= 1;
        timer_a <= {ta_hi, ta_lo};
        countA3 <= 0;
        if (cra[3] | oneShotA0) begin
            cra[0] <= 0;
            countA2 <= 0;
        end
      end

      if (loadA1) begin
        timer_a <= {ta_hi, ta_lo};
        countA3 <= 0;
      end
    end

    if (wr)
      case (rs)
        4'h4:
        begin
            ta_lo <= db_in;
            if (timerAoverflow) timer_a <= {ta_hi, db_in};
        end
        4'h5:
        begin
            ta_hi <= db_in;
            if (~cra[0] | cra[3]) begin
                timer_a <= {db_in, ta_lo};
                countA3 <= cra[3];
					 cra[0] <= cra[3];
            end
        end
        4'he:
        begin
            cra   <= db_in;
            timerAff <= timerAff | (db_in[0] & ~cra[0]);
        end
        default: ;
      endcase;
  end
end

// Timer B
reg countB0, countB1, countB2, countB3, loadB1, oneShotB0;
reg timerBff;
wire timerBin = crb[6] ? timerAoverflow & (~crb[5] | cnt_in) : (~crb[5] | countB1);
wire [15:0] newTimerBVal = countB3 ? (timer_b - 1'b1) : timer_b;
wire timerBoverflow = !newTimerBVal & countB2;

always @(posedge clk) begin

  if (!res_n) begin
    tb_lo          <= 8'hff;
    tb_hi          <= 8'hff;
    crb            <= 8'h00;
    timer_b        <= 16'h0000;
    timerBff       <= 1'b0;
    icr[1]         <= 1'b0;
    timer_b_int    <= 0;
  end
  else begin
    if (phi2_p) begin
      if (int_reset) begin
        icr[1] <= 0;
        timer_b_int <= 0;
      end
      countB0 <= cnt_in && ~cnt_in_prev;
      countB1 <= countB0;
      countB2 <= timerBin & crb[0];
      countB3 <= countB2;
      loadB1 <= crb[4];
      crb[4] <= 0;
      oneShotB0 <= crb[3];
      timer_b <= newTimerBVal;
      if (timerBoverflow) begin
        timerBff <= ~timerBff;
        icr[1] <= 1;
        timer_b_int <= 1;
        timer_b <= {tb_hi, tb_lo};
        countB3 <= 0;
        if (crb[3] | oneShotB0) begin
            crb[0] <= 0;
            countB2 <= 0;
        end
      end

      if (loadB1) begin
        timer_b <= {tb_hi, tb_lo};
        countB3 <= 0;
      end
    end

    if (wr)
      case (rs)
        4'h6:
        begin
            tb_lo <= db_in;
            if (timerBoverflow) timer_b <= {tb_hi, db_in};
        end
        4'h7:
        begin
            tb_hi <= db_in;
            if (~crb[0] | crb[3]) begin
                timer_b <= {db_in, tb_lo};
                countB3 <= crb[3];
					 crb[0] <= crb[3];
            end
        end
        4'hf:
        begin
            crb   <= db_in;
            timerBff <= timerBff | (db_in[0] & ~crb[0]);
        end
        default: ;
      endcase;
  end
end

// Time of Day
always @(posedge clk) begin
  if (!res_n) begin
    tod_run     <= 1'b0;
    tod_alarm   <= 24'h000000;
    tod_latch   <= 24'h000000;
    tod_count   <= 24'h000000;
    tod_latched <= 1'b0;
    icr[2] <= 1'b0;
  end
  else if (rd)
    case (rs)
      4'h8: tod_latched <= 1'b0;
      4'ha: tod_latched <= 1'b1;
      default: ;
    endcase
  else if (wr)
    case (rs)
      4'h8: if (crb[7]) tod_alarm[7:0] <= db_in;
            else begin
              tod_run   <= 1'b1;
              tod_count[7:0] <= db_in;
            end
      4'h9: if (crb[7]) tod_alarm[15:8] <= db_in;
            else tod_count[15:8] <= db_in;
      4'ha: if (crb[7]) tod_alarm[23:16] <= db_in;
            else begin
              tod_run <= 1'b0;
              tod_count[23:16] <= db_in;
            end
      default: ;
    endcase
  tod_prev <= tod;
  if (tod_run && tod && !tod_prev) tod_count <= tod_count + 1'd1;

  if (phi2_p) begin
    if (!tod_latched) tod_latch <= tod_count;
    if (tod_count == tod_alarm) begin
      tod_alarm_reg <= 1'b1;
      icr[2]   <= !tod_alarm_reg ? 1'b1 : icr[2];
    end
    else tod_alarm_reg <= 1'b0;
    if (int_reset) icr[2] <= 1'b0;
  end
end

// Serial Port Input/Output
always @(posedge clk) begin
  if (!res_n) begin
    sdr         <= 8'h00;
    sp_out      <= 1'b1;
    sp_pending  <= 1'b0;
    sp_transmit <= 1'b0;
    sp_shiftreg <= 8'h00;
    icr[3]      <= 1'b0;
    icr3        <= 1'b0;
  end
  else begin
    if (wr)
      case (rs)
        4'hc:
          begin
            sdr <= db_in;
            sp_pending <= 1;
          end
      endcase

    if (!cra[6]) begin // input
      sp_out <= 1'b1;
      if (cnt_in && !cnt_in_prev) sp_shiftreg <= {sp_shiftreg[6:0], sp_in};
		if (!cnt_in && cnt_in_prev && cnt_pulsecnt == 3'h7) begin
        sdr  <= sp_shiftreg;
        icr3 <= 1'b1;
      end
    end
    else begin // output
      if (sp_pending && !sp_transmit) begin
        sp_pending  <= 1'b0;
        sp_transmit <= 1'b1;
        sp_shiftreg <= sdr;
      end
      else if (!cnt_out_r && cnt_out) begin
        if (cnt_pulsecnt == 3'h7) begin
          icr3        <= 1'b1;
          sp_transmit <= 1'b0;
        end
        sp_out      <= sp_shiftreg[7];
        sp_shiftreg <= {sp_shiftreg[6:0], sp_shiftreg[0]};
      end
    end

    if (phi2_p) begin
		if(icr3) icr[3] <= 1'b1;
		icr3 <= 1'b0;
		if(int_reset) icr[3] <= 1'b0;
    end
  end
end

// CNT Input/Output
always @(posedge clk) begin
  if (!res_n) begin
    cnt_out_r    <= 1'b1;
    cnt_out      <= 1'b1;
    cnt_pulsecnt <= 3'h0;
  end
  else begin
    cnt_in_prev <= cnt_in;
    cnt_out <= cnt_out_r;

    if (cra[6] ? (!cnt_out_r && cnt_out) : (!cnt_in && cnt_in_prev)) cnt_pulsecnt <= cnt_pulsecnt + 1'b1;

    if (phi2_p) begin
  	   if (!cra[6]) cnt_out_r <= 1'b1;
      else if (sp_transmit & timerAoverflow) cnt_out_r <= ~cnt_out_r;
    end
  end
end

wire [4:0] icr_adj = {icr[4:2], timer_b_int, icr[0]};

// Interrupt Control
always @(posedge clk) begin
  reg [7:0] imr_reg;

  if (!res_n) begin
    imr       <= 5'h00;
    imr_reg   <= 0;
    irq_n     <= 1'b1;
    int_reset <= 0;
  end
  else begin
    if (wr && rs == 4'hd) imr_reg <= db_in;
    if (rd && rs == 4'hd) int_reset <= 1;

    imr <= imr_reg[7] ? imr | imr_reg[4:0] : imr & ~imr_reg[4:0];
    irq_n <= irq_n ? ~|(imr & icr_adj) : irq_n;
    if (phi2_p & int_reset) begin
      irq_n <= 1;
	  int_reset <= 0;
    end
  end
end

endmodule
