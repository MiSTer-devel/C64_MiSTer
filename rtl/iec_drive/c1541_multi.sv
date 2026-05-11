//-------------------------------------------------------------------------------
//
// C1541 multi-drive implementation with shared ROM
// (C) 2021 Alexey Melnikov
//
// Input clock/ce 16MHz
//
//
// DDRAM arbiter by Robin Wünderlich
//-------------------------------------------------------------------------------


module c1541_multi #(parameter PARPORT=1,DUALROM=1,DRIVES=2)
(
	//clk ports
	input         clk,
	input   [N:0] reset,
	input         ce,

	input         pause,
	input   [N:0] gcr_mode,

	input   [N:0] img_mounted,
	input         img_readonly,
	input  [31:0] img_size,
	input   [2:0] drive_rpm,
	input         drive_wobble,

	output  [N:0] led,
	output wire [6:0] out_track[NDR],
	output wire [N:0] out_we,
	output        disk_ready,

	input         iec_atn_i,
	input         iec_data_i,
	input         iec_clk_i,
	output        iec_data_o,
	output        iec_clk_o,

	// parallel bus
	input   [7:0] par_data_i,
	input         par_stb_i,
	output  [7:0] par_data_o,
	output        par_stb_o,

	//clk_sys ports
	input         clk_sys,

	output [31:0] sd_lba[NDR],
	output  [5:0] sd_blk_cnt[NDR],
	output  [N:0] sd_rd,
	output  [N:0] sd_wr,
	input   [N:0] sd_ack,
	input  [13:0] sd_buff_addr,
	input   [7:0] sd_buff_dout,
	output  [7:0] sd_buff_din[NDR],
	input         sd_buff_wr,

	input  [14:0] rom_addr,
	input   [7:0] rom_data,
	input         rom_wr,
	input         rom_std,

	input         DDRAM_BUSY,
	output  [7:0] DDRAM_BURSTCNT,
	output [28:0] DDRAM_ADDR,
	input  [63:0] DDRAM_DOUT,
	input         DDRAM_DOUT_READY,
	output        DDRAM_RD,
	output        DDRAM_WE,
	output [63:0] DDRAM_DIN,
	output  [7:0] DDRAM_BE
);

localparam NDR = (DRIVES < 1) ? 1 : (DRIVES > 4) ? 4 : DRIVES;
localparam N   = NDR - 1;

wire iec_atn, iec_data, iec_clk;
iecdrv_sync atn_sync(clk, iec_atn_i,  iec_atn);
iecdrv_sync dat_sync(clk, iec_data_i, iec_data);
iecdrv_sync clk_sync(clk, iec_clk_i,  iec_clk);

wire [N:0] reset_drv;
iecdrv_sync #(NDR) rst_sync(clk, reset, reset_drv);

wire stdrom = (DUALROM || PARPORT) ? rom_std : 1'b1;

reg ph2_r;
reg ph2_f;
always @(posedge clk) begin
	reg [3:0] div;
	reg       ena, ena1;

	ena1 <= ~pause;
	if(div[2:0]) ena <= ena1;

	ph2_r <= 0;
	ph2_f <= 0;
	if(ce) begin
		div <= div + 1'd1;
		ph2_r <= ena && !div[3] && !div[2:0];
		ph2_f <= ena &&  div[3] && !div[2:0];
	end
end

initial begin
	rom_32k_i = 1;
	rom_16k_i = 1;
end

reg rom_32k_i;
reg rom_16k_i;
always @(posedge clk_sys) if (rom_wr & |rom_data & ~&rom_data) {rom_32k_i,rom_16k_i} <= rom_addr[14:13];

reg [1:0] rom_sz;
always @(posedge clk) rom_sz <= {rom_32k_i,rom_32k_i|rom_16k_i}; // support for 8K/16K/32K ROM

wire [7:0] rom_do;
generate
	if(PARPORT) begin
		iecdrv_mem #(8,15,"rtl/iec_drive/c1541_dolphin.mif") rom
		(
			.clock_a(clk_sys),
			.address_a(rom_addr),
			.data_a(rom_data),
			.wren_a(rom_wr),

			.clock_b(clk),
			.address_b(mem_a),
			.q_b(rom_do)
		);
	end
	else if(DUALROM) begin
		iecdrv_mem #(8,14,"rtl/iec_drive/c1541_rom.mif") rom
		(
			.clock_a(clk_sys),
			.address_a(rom_addr[13:0]),
			.data_a(rom_data),
			.wren_a(rom_wr),

			.clock_b(clk),
			.address_b(mem_a[13:0]),
			.q_b(rom_do)
		);
	end
	else begin
		assign rom_do = romstd_do;
	end
endgenerate

wire [7:0] romstd_do;
iecdrv_mem #(8,14,"rtl/iec_drive/c1541_rom.mif") romstd
(
	.clock_a(clk_sys),
	.address_a(rom_addr[13:0]),
	.data_a(rom_data),
	.wren_a((DUALROM || PARPORT) ? 1'b0 : rom_wr),

	.clock_b(clk),
	.address_b(mem_a[13:0]),
	.q_b(romstd_do)
);

reg  [14:0] mem_a;
wire [14:0] drv_addr[NDR];
reg   [7:0] drv_data[4];
always @(posedge clk) begin
	reg [2:0] state;
	reg [14:0] mem_d;
	
	if(~&state) state <= state + 1'd1;
	if(ph2_f)   state <= 0;

	case(state)
		0,1,2,3: mem_a <= {drv_addr[state[1:0]][14] & rom_sz[1], drv_addr[state[1:0]][13] & (rom_sz[0] | stdrom), drv_addr[state[1:0]][12:0]};
	endcase
	
	case(state)
		3,4,5,6: drv_data[state[1:0] - 2'd3] <= stdrom ? romstd_do : rom_do;
	endcase
end

wire [N:0] iec_data_d, iec_clk_d;
assign     iec_clk_o  = &{iec_clk_d  | reset_drv};
assign     iec_data_o = &{iec_data_d | reset_drv};

wire [N:0] ext_en = {NDR{rom_sz[1] & ~stdrom & |PARPORT}} & ~reset_drv;
wire [7:0] par_data_d[NDR];
wire [N:0] par_stb_d;
assign     par_stb_o = &{par_stb_d | ~ext_en};
always_comb begin
	par_data_o = 8'hFF;
	for(int i=0; i<NDR; i=i+1) if(ext_en[i]) par_data_o = par_data_o & par_data_d[i];
end

wire [N:0] led_drv;
assign     led = led_drv & ~reset_drv;

wire [N:0] i_disk_ready;
assign     disk_ready = &(i_disk_ready | reset_drv);

generate
	genvar i;
	for(i=0; i<NDR; i=i+1) begin :drives
		c1541_drv c1541_drv
		(
			.clk(clk),
			.reset(reset_drv[i]),

			.gcr_mode(gcr_mode[i]),

			.ce(ce),
			.ph2_r(ph2_r),
			.ph2_f(ph2_f),

			.img_mounted(img_mounted[i]),
			.img_readonly(img_readonly),
			.img_size(img_size),
			.drive_rpm(drive_rpm),
			.drive_wobble(drive_wobble),

			.drive_num(i),
			.led(led_drv[i]),
			.out_track(out_track[i]),
			.out_we(out_we[i]),
			.disk_ready(i_disk_ready[i]),

			.iec_atn_i(iec_atn),
			.iec_data_i(iec_data & iec_data_o),
			.iec_clk_i(iec_clk & iec_clk_o),
			.iec_data_o(iec_data_d[i]),
			.iec_clk_o(iec_clk_d[i]),

			.par_data_i(par_data_i),
			.par_stb_i(par_stb_i),
			.par_data_o(par_data_d[i]),
			.par_stb_o(par_stb_d[i]),

			.ext_en(ext_en[i]),
			.rom_addr(drv_addr[i]),
			.rom_data(drv_data[i]),

			.clk_sys(clk_sys),

			.sd_lba(sd_lba[i]),
			.sd_blk_cnt(sd_blk_cnt[i]),
			.sd_rd(sd_rd[i]),
			.sd_wr(sd_wr[i]),
			.sd_ack(sd_ack[i]),
			.sd_buff_addr(sd_buff_addr),
			.sd_buff_dout(sd_buff_dout),
			.sd_buff_din(sd_buff_din[i]),
			.sd_buff_wr(sd_buff_wr),

			.DDRAM_BUSY(arb_ddram_busy[i]),
			.DDRAM_DOUT(DDRAM_DOUT),
			.DDRAM_DOUT_READY(arb_ddram_ready[i]),
			.DDRAM_BURSTCNT(drv_ddram_burstcnt[i]),
			.DDRAM_ADDR(drv_ddram_addr[i]),
			.DDRAM_RD(drv_ddram_rd[i]),
			.DDRAM_WE(drv_ddram_we[i]),
			.DDRAM_DIN(drv_ddram_din[i]),
			.DDRAM_BE(drv_ddram_be[i])
		);
	end
endgenerate

wire [7:0]  drv_ddram_burstcnt[NDR];
wire [28:0] drv_ddram_addr[NDR];
wire        arb_ddram_busy[NDR];
wire        arb_ddram_ready[NDR];
wire        drv_ddram_rd[NDR];
wire        drv_ddram_we[NDR];
wire [63:0] drv_ddram_din[NDR];
wire  [7:0] drv_ddram_be[NDR];

// ==============================================================================
// DDRAM Round-Robin Arbiter (Supports Read Bursts)
// ==============================================================================

reg [1:0] arb_rr_state;
reg       arb_is_locked;
reg [7:0] burst_remaining;

// MUX: Route signals for the currently polled/active drive
assign DDRAM_ADDR     = drv_ddram_addr[arb_rr_state];
assign DDRAM_DIN      = drv_ddram_din[arb_rr_state];
assign DDRAM_BE       = drv_ddram_be[arb_rr_state];
assign DDRAM_BURSTCNT = drv_ddram_burstcnt[arb_rr_state];

// Only assert RD/WE if the bus isn't locked by an ongoing fetch
assign DDRAM_RD = arb_is_locked ? 1'b0 : drv_ddram_rd[arb_rr_state];
assign DDRAM_WE = arb_is_locked ? 1'b0 : drv_ddram_we[arb_rr_state];

// BUSY Router: Drive must wait if it's not being polled, bus is locked, or RAM is busy
generate
	genvar arb_i;
	for(arb_i=0; arb_i<NDR; arb_i=arb_i+1) begin : arb_routing_gen
		// Force drive to wait if not polled, bus locked, or RAM busy
		assign arb_ddram_busy[arb_i]  = (arb_rr_state != arb_i[1:0]) || arb_is_locked || DDRAM_BUSY;
		// Only pass the ready pulse to the drive that currently owns the lock
		assign arb_ddram_ready[arb_i] = (arb_rr_state == arb_i[1:0] && arb_is_locked) ? DDRAM_DOUT_READY : 1'b0;
	end
endgenerate

// Polling and Burst-Lock FSM
always @(posedge clk_sys) begin
	if (&reset) begin
		arb_is_locked   <= 1'b0;
		arb_rr_state    <= 2'd0;
		burst_remaining <= 8'd0;
	end else begin
		if (!arb_is_locked) begin
			// POLLING: Check if the current drive wants the bus
			if (!DDRAM_BUSY) begin
				if (drv_ddram_rd[arb_rr_state]) begin
					arb_is_locked   <= 1'b1; // Lock bus for the duration of the burst
					burst_remaining <= drv_ddram_burstcnt[arb_rr_state];
				end else if (!drv_ddram_we[arb_rr_state]) begin
					// No request, move to next drive
					arb_rr_state <= (arb_rr_state == N) ? 2'd0 : arb_rr_state + 2'd1;
				end
			end
		end else begin
			// LOCKED: Wait for the burst to complete
			if (DDRAM_DOUT_READY) begin
				if (burst_remaining <= 8'd1) begin
					arb_is_locked <= 1'b0; // Unlock immediately
					// Move to next drive to ensure fairness
					arb_rr_state  <= (arb_rr_state == N) ? 2'd0 : arb_rr_state + 2'd1;
				end else begin
					burst_remaining <= burst_remaining - 8'd1;
				end
			end
		end
	end
end

endmodule
