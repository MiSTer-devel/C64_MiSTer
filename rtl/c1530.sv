//-----------------------------------------------------------------------------
// Commodore 1530 to SD card host (read only)
// Originally VHDL by Dar (darfpga@aol.fr) 25-Mars-2019
// tap/wav player - Converted to 8 bit FIFO by Slingshot
// SystemVerilog conversion for MiSTer
//-----------------------------------------------------------------------------

module c1530 (
	input  logic        clk32,
	input  logic        restart_tape,
	input  logic        wav_mode,
	input  logic [1:0]  tap_version,
	input  logic [7:0]  host_tap_in,
	input  logic        host_tap_wrreq,
	output logic        tap_fifo_wrfull,
	output logic        tap_fifo_error,
	input  logic        cass_sense,
	output logic        cass_read,
	input  logic        cass_write,
	input  logic        cass_motor,
	output logic        cass_run
);

logic [5:0]  tap_player_tick_cnt;
logic [11:0] wav_player_tick_cnt;
logic [23:0] wave_cnt;
logic [23:0] wave_len;
logic [7:0]  tap_fifo_do;
logic        tap_fifo_rdreq;
logic        tap_fifo_empty;
logic        get_24bits_len;
logic [7:0]  start_bytes;
logic        initial_delay;
logic        skip_bytes;

logic        cass_motor_D;
logic        motor;
logic [23:0] motor_counter;

tap_fifo tap_fifo_inst (
	.aclr  (restart_tape),
	.data  (host_tap_in),
	.clock (clk32),
	.rdreq (tap_fifo_rdreq),
	.wrreq (host_tap_wrreq),
	.q     (tap_fifo_do),
	.empty (tap_fifo_empty),
	.full  (tap_fifo_wrfull)
);

always_ff @(posedge clk32 or posedge restart_tape) begin
	if (restart_tape) begin
		{start_bytes, skip_bytes, get_24bits_len} <= {8'h00, 1'b1, 1'b0};
		{tap_player_tick_cnt, wav_player_tick_cnt} <= 18'h00000;
		wave_len  <= 24'h000004;
		wave_cnt  <= 24'h000000;
		initial_delay   <= 1'b1;
		tap_fifo_rdreq  <= 1'b0;
		tap_fifo_error  <= 1'b0;
		{motor, cass_read} <= 2'b11;
	end else begin
		// simulate tape motor momentum
		cass_motor_D <= cass_motor;
		if (cass_motor_D != cass_motor)
			motor_counter <= 24'd320000;
		else if (motor_counter != 0)
			motor_counter <= motor_counter - 1'b1;
		else
			motor <= cass_motor;

		tap_fifo_rdreq <= 1'b0;

		if (~motor & ~cass_sense) begin

			if (wav_mode) begin
				wav_player_tick_cnt <= wav_player_tick_cnt + 1'b1;
				if (wav_player_tick_cnt == 12'h2F0) begin
					wav_player_tick_cnt <= 12'h000;
					{tap_fifo_error, tap_fifo_rdreq} <= tap_fifo_empty ? 2'b10 : 2'b01;
				end
				cass_read <= ~tap_fifo_do[7];
			end else begin
				tap_player_tick_cnt <= tap_player_tick_cnt + 1'b1;

				if ((tap_player_tick_cnt == 6'h1F) & ~skip_bytes) begin

					if (~tap_version[1]) begin
						if (wave_cnt > {14'b0, wave_len[10:1]})
							cass_read <= 1'b1;
						else
							cass_read <= 1'b0;
					end

					tap_player_tick_cnt <= 6'h00;
					wave_cnt <= wave_cnt + 1'b1;

					if (wave_cnt == wave_len - 1'b1) begin
						wave_cnt <= 24'h000000;
						if (tap_version == 2'd2)
							cass_read <= ~cass_read;

						if (tap_fifo_empty) begin
							tap_fifo_error <= 1'b1;
						end else begin
							tap_fifo_rdreq <= 1'b1;
							if (tap_fifo_do == 8'h00) begin
								wave_len       <= 24'h000100;
								get_24bits_len <= tap_version[0] | tap_version[1];
							end else begin
								{initial_delay, wave_len} <= {1'b0, 13'b0, tap_fifo_do, 3'b000};
							end
						end
					end
				end

				// catch 24bits wave_len for data x00 in tap version 1,2
				if (get_24bits_len & ~skip_bytes & tap_player_tick_cnt[0]) begin
					if (tap_player_tick_cnt == 6'h05)
						get_24bits_len <= 1'b0;

					if (tap_fifo_empty) begin
						tap_fifo_error <= 1'b1;
					end else begin
						tap_fifo_rdreq <= 1'b1;
						wave_len <= {tap_fifo_do, wave_len[23:8]};
						if (initial_delay)
							wave_len <= 24'h000004;
					end

					if (~tap_version[1])
						cass_read <= 1'b1;
				end

				// skip tap header bytes
				if (skip_bytes & ~tap_fifo_empty & tap_player_tick_cnt[0]) begin
					{tap_fifo_rdreq, cass_read} <= 2'b11;
					if (start_bytes < 8'h14)
						start_bytes <= start_bytes + 8'h01;
					else
						skip_bytes <= 1'b0;
				end
			end

		end else begin
			cass_read <= 1'b1;
			tap_player_tick_cnt <= tap_player_tick_cnt + 1'b1;
		end
	end
end

assign cass_run = motor;

endmodule


//-----------------------------------------------------------------------------
// Altera scfifo wrapper for c1530 tape data buffer
//-----------------------------------------------------------------------------

module tap_fifo (
	input  logic        aclr,
	input  logic        clock,
	input  logic [7:0]  data,
	input  logic        rdreq,
	input  logic        wrreq,
	output logic        empty,
	output logic        full,
	output logic [7:0]  q
);

scfifo #(
	.add_ram_output_register ("OFF"),
	.intended_device_family  ("Cyclone III"),
	.lpm_numwords            (64),
	.lpm_showahead           ("OFF"),
	.lpm_type                ("scfifo"),
	.lpm_width               (8),
	.lpm_widthu              (6),
	.overflow_checking       ("ON"),
	.underflow_checking      ("ON"),
	.use_eab                 ("ON")
) scfifo_component (
	.aclr  (aclr),
	.clock (clock),
	.data  (data),
	.rdreq (rdreq),
	.wrreq (wrreq),
	.empty (empty),
	.full  (full),
	.q     (q)
);

endmodule
