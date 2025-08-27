//
//  AM29F040 (512K x 8) parallel NOR flash
//  Copyright (C) 2025 Alexey Melnikov
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//============================================================================

module am29f040 #(
	parameter int ADDR_WIDTH           = 19,       // 512 KiB address space
	parameter int SECTOR_COUNT         = 8,
	parameter logic [7:0] MANUF_ID     = 8'h01,    // AMD
	parameter logic [7:0] DEVICE_ID    = 8'hA4,    // AM29F040
	parameter int PROG_LATENCY_CYC     = 32,       // 7us
	parameter int SECTOR_ERASE_LAT_CYC = 1000000,  // 1sec for sector erase
	parameter int CHIP_ERASE_LAT_CYC   = SECTOR_COUNT * SECTOR_ERASE_LAT_CYC  // cycles for chip erase
)(
	input  logic                    clk,
	input  logic                    reset_n,

	input  logic                    ce_n, // strobe, must be active only 1 cycle
	input  logic                    we_n,
	input  logic [ADDR_WIDTH-1:0]   addr,
	input  logic [7:0]              dq_in,
	output logic [7:0]              dq_out,
	output logic                    dq_oe,

	input  logic                    mem_cycle,
	output logic [ADDR_WIDTH-1:0]   mem_addr,
	input  logic [7:0]              mem_in,
	output logic [7:0]              mem_out,
	output logic                    mem_ce,
	output logic                    mem_we,

	//arbiter
	output logic                    mem_req
);

localparam int MEM_BYTES   = 1 << ADDR_WIDTH;
localparam int SECTOR_MASK = (MEM_BYTES / SECTOR_COUNT) - 1;

// Unlock tracking
localparam logic [10:0] UNLOCK_ADDR1 = 11'h555;
localparam logic [10:0] UNLOCK_ADDR2 = 11'h2AA;
localparam logic  [7:0] UNLOCK_DATA1 = 8'hAA;
localparam logic  [7:0] UNLOCK_DATA2 = 8'h55;

wire IS_UNLOCK_ADDR1 = (addr[10:0] == UNLOCK_ADDR1);
wire IS_UNLOCK_ADDR2 = (addr[10:0] == UNLOCK_ADDR2);
wire UNLOCK1 = IS_UNLOCK_ADDR1 && (dq_in == UNLOCK_DATA1);
wire UNLOCK2 = IS_UNLOCK_ADDR2 && (dq_in == UNLOCK_DATA2);


// Command codes (byte mode)
localparam byte CMD_AUTOSEL     = 8'h90;
localparam byte CMD_RESET       = 8'hF0;
localparam byte CMD_RESET2      = 8'hFF;
localparam byte CMD_PROG        = 8'hA0;
localparam byte CMD_ERASE       = 8'h80;
localparam byte CMD_ERASE_CHIP  = 8'h10;
localparam byte CMD_ERASE_SECT  = 8'h30;

typedef enum logic [2:0]
{
	ST_READ_MEM,
	ST_AUTOSEL,
	ST_ERASE,
	ST_DQ_WR,
	ST_BUSY
} state_e;
state_e state;

typedef enum logic [2:0]
{
	U_IDLE,
	U_STEP1,
	U_STEP2,
	U_STEP3,
	U_STEP4
} unlock_e;
unlock_e unlock;

// DQ6 toggle and DQ7 data polling
logic dq6_toggle;
logic dq7_data;
logic dq3_data;

logic                  mem_req_we;
logic [ADDR_WIDTH-1:0] mem_req_addr;
logic            [7:0] mem_req_out;
logic [ADDR_WIDTH-1:0] mem_req_cnt;
logic           [31:0] busy_cnt;

assign mem_addr = mem_req_addr;
assign mem_out  = mem_req_out;
assign mem_ce   = mem_req & mem_cycle;
assign mem_we   = mem_req & mem_req_we & mem_cycle;

always_comb begin
	dq_out = mem_in;
	dq_oe = 0;
	case(state)
		ST_BUSY: begin
			dq_out[3] = dq3_data;
			dq_out[5] = 0;
			dq_out[6] = dq6_toggle; // DQ6 toggles while busy
			dq_out[7] = dq7_data;   // DQ7 reflects programmed MSB when done; here we show target value while busy
			dq_oe = 1;
		end

		ST_AUTOSEL: begin
			     if (addr[7:0] == 0) dq_out = MANUF_ID;
			else if (addr[7:0] == 1) dq_out = DEVICE_ID;
			else dq_out = 8'h00;    // protect bits are not implemented
			dq_oe = 1;
		end
		
		default:;
	endcase
end

always_ff @(posedge clk or negedge reset_n) begin
	logic [2:0] ce_stage;

	if (!reset_n) begin
		state      <= ST_READ_MEM;
		unlock     <= U_IDLE;
		mem_req    <= 0;
	end else begin

		ce_stage <= {ce_stage[1:0], mem_req && ~mem_req_we && mem_cycle};
		if(~ce_n) dq6_toggle <= ~dq6_toggle;

		// Memory access
		if(mem_req) begin
			if(~mem_req_we && ce_stage[2]) begin
				mem_req_out <= mem_req_out & mem_in;
				mem_req_we <= 1;
			end

			if(mem_req_we && mem_cycle) begin
				mem_req_addr <= mem_req_addr + 1'd1;
				mem_req_cnt <= mem_req_cnt - 1'd1;
				if(!mem_req_cnt) mem_req <= 0;
			end
		end

		if(state == ST_BUSY) begin
			if(busy_cnt) busy_cnt <= busy_cnt - 1;
			else if(!mem_req) state <= ST_READ_MEM;
		end

		if(~ce_n && ~we_n) begin
			case (state)
				ST_READ_MEM: begin
					// Command state machine with unlock sequence AA->55->CMD to 0x555/0x2AA/0x555
					case (unlock)
						U_IDLE: begin
							// CMD_RESET, CMD_RESET2 or Unknown command or address -> idle
							unlock <= UNLOCK1 ? U_STEP1 : U_IDLE;
						end

						U_STEP1: begin
							unlock <= UNLOCK2 ? U_STEP2 : U_IDLE;
						end

						U_STEP2: begin
							unlock <= U_IDLE;
							// Third write determines command; must be to 0x555
							// CMD_RESET, CMD_RESET2 or Unknown command or address -> idle
							if (IS_UNLOCK_ADDR1) begin
								case (dq_in)
									CMD_AUTOSEL: state  <= ST_AUTOSEL;
									CMD_PROG:    state  <= ST_DQ_WR; // Next write will be data/address
									CMD_ERASE:   unlock <= U_STEP3; // Expect AA->55->(80) then AA->55->(30/10)
								endcase
							end
						end

						U_STEP3: begin
							unlock <= UNLOCK1 ? U_STEP4 : U_IDLE;
						end

						U_STEP4: begin
							unlock <= U_IDLE;
							if(UNLOCK2) state <= ST_ERASE;
						end
					endcase
				end
				
				ST_AUTOSEL: begin
					state <= ST_READ_MEM;
				end

				ST_ERASE: begin
					mem_req_out <= 8'hFF;
					mem_req_we  <= 1;
					dq3_data    <= 1;
					dq7_data    <= 0;
					state       <= ST_READ_MEM;
					if (dq_in == CMD_ERASE_SECT) begin
						busy_cnt     <= SECTOR_ERASE_LAT_CYC;
						mem_req_addr <= addr & ~SECTOR_MASK[ADDR_WIDTH-1:0];
						mem_req_cnt  <= SECTOR_MASK[ADDR_WIDTH-1:0];
						mem_req      <= 1;
						state        <= ST_BUSY;
					end else if (IS_UNLOCK_ADDR1 && (dq_in == CMD_ERASE_CHIP)) begin
						busy_cnt     <= CHIP_ERASE_LAT_CYC;
						mem_req_addr <= 0;
						mem_req_cnt  <= '1;
						mem_req      <= 1;
						state        <= ST_BUSY;
					end
				end

				ST_DQ_WR: begin
					// Treat as program data write to target address
					busy_cnt     <= PROG_LATENCY_CYC;
					mem_req_addr <= addr;
					mem_req_cnt  <= 0;
					mem_req_out  <= dq_in;
					mem_req_we   <= 0;
					mem_req      <= 1;
					dq3_data     <= 0;
					dq7_data     <= ~dq_in[7];
					state        <= ST_BUSY;
				end
			endcase
		end
	end
end

endmodule

module ez_rom
(
	input  logic        clk,
	input  logic        reset_n,
	input  logic        ce,
	input  logic        we,
	input  logic [19:0] addr,
	input  logic [7:0]  dq_in,
	output logic [7:0]  dq_out,
	output logic        dq_oe, 

	output logic        mem_req,
	input  logic        mem_cycle,
	output logic        mem_oe,

	output logic [19:0] mem_addr,
	input  logic [7:0]  mem_in,
	output logic [7:0]  mem_out,
	output logic        mem_ce,
	output logic        mem_we
);

logic  [7:0] dq0_out;
logic        dq0_oe;
logic [18:0] mem0_addr;
logic  [7:0] mem0_out;
logic        mem0_ce;
logic        mem0_we;
logic        mem0_req;

am29f040 rom0
(
	.clk(clk),
	.reset_n(reset_n),
	.ce_n(~ce || addr[19]),
	.we_n(~we),
	.addr(addr[18:0]),
	.dq_in(dq_in),
	.dq_out(dq0_out),
	.dq_oe(dq0_oe),

	.mem_cycle(mem_oe & ~mem_rom_sel),
	.mem_addr(mem0_addr),
	.mem_in(mem_in),
	.mem_out(mem0_out),
	.mem_ce(mem0_ce),
	.mem_we(mem0_we),

	.mem_req(mem0_req)
);

logic  [7:0] dq1_out;
logic        dq1_oe;
logic [18:0] mem1_addr;
logic  [7:0] mem1_out;
logic        mem1_ce;
logic        mem1_we;
logic        mem1_req;

am29f040 rom1
(
	.clk(clk),
	.reset_n(reset_n),
	.ce_n(~ce || ~addr[19]),
	.we_n(~we),
	.addr(addr[18:0]),
	.dq_in(dq_in),
	.dq_out(dq1_out),
	.dq_oe(dq1_oe),

	.mem_cycle(mem_oe & mem_rom_sel),
	.mem_addr(mem1_addr),
	.mem_in(mem_in),
	.mem_out(mem1_out),
	.mem_ce(mem1_ce),
	.mem_we(mem1_we),

	.mem_req(mem1_req)
);

assign dq_out = addr[19] ? dq1_out : dq0_out;
assign dq_oe  = addr[19] ? dq1_oe : dq0_oe;
assign mem_req = mem0_req | mem1_req;


logic mem_req_en;
logic mem_cycle_q;
always_ff @(posedge clk) begin
	if(~reset_n || ~mem_req) mem_req_en <= 0;
	else if(mem_req & mem_cycle) mem_req_en <= 1;
	mem_cycle_q <= mem_cycle;
end

assign mem_oe = ~mem_cycle_q & mem_cycle & mem_req_en;

logic mem_rom_sel;
always_ff @(posedge clk) begin
	if(mem_oe) begin
		if(mem0_req && mem1_req) mem_rom_sel <= ~mem_rom_sel;
		else if(mem0_req) mem_rom_sel <= 0;
		else if(mem1_req) mem_rom_sel <= 1;
	end
end

assign mem_addr = mem_rom_sel ? {1'b1, mem1_addr} : {1'b0, mem0_addr};
assign mem_out  = mem_rom_sel ?         mem1_out  :         mem0_out;
assign mem_ce   = mem1_ce | mem0_ce;
assign mem_we   = mem1_we | mem0_we;

endmodule
