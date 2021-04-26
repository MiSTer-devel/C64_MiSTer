//============================================================================
//  C64 Top level for MiSTer
//  Copyright (C) 2017-2019 Sorgelig
//
//  Used DE2-35 Top level by Dar (darfpga@aol.fr)
//
//  FPGA64 is Copyrighted 2005-2008 by Peter Wendrich (pwsoft@syntiac.com)
//  http://www.syntiac.com/fpga64.html
//
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

module emu
(
	//Master input clock
	input         CLK_50M,

	//Async reset from top-level module.
	//Can be used as initial reset.
	input         RESET,

	//Must be passed to hps_io module
	inout  [45:0] HPS_BUS,

	//Base video clock. Usually equals to CLK_SYS.
	output        CLK_VIDEO,

	//Multiple resolutions are supported using different CE_PIXEL rates.
	//Must be based on CLK_VIDEO
	output        CE_PIXEL,

	//Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
	//if VIDEO_ARX[12] or VIDEO_ARY[12] is set then [11:0] contains scaled size instead of aspect ratio.
	output [12:0] VIDEO_ARX,
	output [12:0] VIDEO_ARY,

	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_DE,    // = ~(VBlank | HBlank)
	output        VGA_F1,
	output [1:0]  VGA_SL,
	output        VGA_SCALER, // Force VGA scaler

	input  [11:0] HDMI_WIDTH,
	input  [11:0] HDMI_HEIGHT,

`ifdef MISTER_FB
	// Use framebuffer in DDRAM (USE_FB=1 in qsf)
	// FB_FORMAT:
	//    [2:0] : 011=8bpp(palette) 100=16bpp 101=24bpp 110=32bpp
	//    [3]   : 0=16bits 565 1=16bits 1555
	//    [4]   : 0=RGB  1=BGR (for 16/24/32 modes)
	//
	// FB_STRIDE either 0 (rounded to 256 bytes) or multiple of pixel size (in bytes)
	output        FB_EN,
	output  [4:0] FB_FORMAT,
	output [11:0] FB_WIDTH,
	output [11:0] FB_HEIGHT,
	output [31:0] FB_BASE,
	output [13:0] FB_STRIDE,
	input         FB_VBL,
	input         FB_LL,
	output        FB_FORCE_BLANK,

`ifdef MISTER_FB_PALETTE
	// Palette control for 8bit modes.
	// Ignored for other video modes.
	output        FB_PAL_CLK,
	output  [7:0] FB_PAL_ADDR,
	output [23:0] FB_PAL_DOUT,
	input  [23:0] FB_PAL_DIN,
	output        FB_PAL_WR,
`endif
`endif

	output        LED_USER,  // 1 - ON, 0 - OFF.

	// b[1]: 0 - LED status is system status OR'd with b[0]
	//       1 - LED status is controled solely by b[0]
	// hint: supply 2'b00 to let the system control the LED.
	output  [1:0] LED_POWER,
	output  [1:0] LED_DISK,

	// I/O board button press simulation (active high)
	// b[1]: user button
	// b[0]: osd button
	output  [1:0] BUTTONS,

	input         CLK_AUDIO, // 24.576 MHz
	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R,
	output        AUDIO_S,   // 1 - signed audio samples, 0 - unsigned
	output  [1:0] AUDIO_MIX, // 0 - no mix, 1 - 25%, 2 - 50%, 3 - 100% (mono)

	//ADC
	inout   [3:0] ADC_BUS,

	//SD-SPI
	output        SD_SCK,
	output        SD_MOSI,
	input         SD_MISO,
	output        SD_CS,
	input         SD_CD,

	//High latency DDR3 RAM interface
	//Use for non-critical time purposes
	output        DDRAM_CLK,
	input         DDRAM_BUSY,
	output  [7:0] DDRAM_BURSTCNT,
	output [28:0] DDRAM_ADDR,
	input  [63:0] DDRAM_DOUT,
	input         DDRAM_DOUT_READY,
	output        DDRAM_RD,
	output [63:0] DDRAM_DIN,
	output  [7:0] DDRAM_BE,
	output        DDRAM_WE,

	//SDRAM interface with lower latency
	output        SDRAM_CLK,
	output        SDRAM_CKE,
	output [12:0] SDRAM_A,
	output  [1:0] SDRAM_BA,
	inout  [15:0] SDRAM_DQ,
	output        SDRAM_DQML,
	output        SDRAM_DQMH,
	output        SDRAM_nCS,
	output        SDRAM_nCAS,
	output        SDRAM_nRAS,
	output        SDRAM_nWE,

`ifdef MISTER_DUAL_SDRAM
	//Secondary SDRAM
	//Set all output SDRAM_* signals to Z ASAP if SDRAM2_EN is 0
	input         SDRAM2_EN,
	output        SDRAM2_CLK,
	output [12:0] SDRAM2_A,
	output  [1:0] SDRAM2_BA,
	inout  [15:0] SDRAM2_DQ,
	output        SDRAM2_nCS,
	output        SDRAM2_nCAS,
	output        SDRAM2_nRAS,
	output        SDRAM2_nWE,
`endif

	input         UART_CTS,
	output        UART_RTS,
	input         UART_RXD,
	output        UART_TXD,
	output        UART_DTR,
	input         UART_DSR,

	// Open-drain User port.
	// 0 - D+/RX
	// 1 - D-/TX
	// 2..6 - USR2..USR6
	// Set USER_OUT to 1 to read from USER_IN.
	input   [6:0] USER_IN,
	output  [6:0] USER_OUT,

	input         OSD_STATUS
);

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign UART_RTS = UART_CTS;
assign UART_DTR = UART_DSR;

assign {DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_DIN, DDRAM_BE, DDRAM_RD, DDRAM_WE} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
//assign {UART_RTS, UART_TXD, UART_DTR} = 0;

assign LED_DISK = 0;
assign LED_POWER = 0;
assign LED_USER = c1541_1_led | c1541_2_led | ioctl_download | tape_led;
assign BUTTONS   = 0;
assign VGA_SCALER = 0;

// Status Bit Map:
//              Upper                          Lower
// 0         1         2         3          4         5         6
// 01234567890123456789012345678901 23456789012345678901234567890123
// 0123456789ABCDEFGHIJKLMNOPQRSTUV 0123456789ABCDEFGHIJKLMNOPQRSTUV
// XXXXXXXXXXXXXXXXXXXXXXXX XXXXXXX XXXX XX XX

`include "build_id.v"
localparam CONF_STR = {
	"C64;UART2400;",
	"h0-;",
	"S0,D64T64,Mount Drive #8;",
	"H0S1,D64T64,Mount Drive #9;",
	"-;",
	"F4,PRG,Load File;",
	"F5,CRT,Load Cartridge;",
	"-;",
	"F6,TAP,Load Tape;",
	"h3R7,Tape Play/Pause;",
	"h3RN,Tape Unload;",
	"h3OB,Tape Sound,Off,On;",
	"-;",

	"P1,Audio & Video;", 
	"P1O2,Video Standard,PAL,NTSC;",
	"P1O45,Aspect Ratio,Original,Full Screen,[ARC1],[ARC2];",
	"P1O8A,Scandoubler Fx,None,HQ2x-320,HQ2x-160,CRT 25%,CRT 50%,CRT 75%;",
	"H2d1P1o0,Vertical Crop,No,Yes;",
	"h2d1P1o01,Vertical Crop,No,270,216;",
	"P1OUV,Scale,Normal,V-Integer,Narrower HV-Integer,Wider HV-Integer;",
	"P1-;",
	"P1OD,Left SID,6581,8580;",
	"D4P1o23,Left Filter,Default,Custom 1,Custom 2,Custom 3;",
	"P1OG,Right SID,6581,8580;",
	"D5P1o56,Right Filter,Default,Custom 1,Custom 2,Custom 3;",
	"P1OKM,Right SID Port,Same,DE00,D420,D500,DF00;",
	"P1FC7,FLT,Load Custom Filters;",
	"P1-;",
	"P1OC,Sound Expander,Disabled,OPL2;",
	"P1o89,DigiMax,Disabled,DE00,DF00;",
	"P1OIJ,Stereo Mix,None,25%,50%,100%;",

	"P2,Hardware;", 
	"P2-;",
	"P2OP,Enable Drive #9,No,Yes;",
	"P2R6,Reset Disk Drives;",
	"P2-;",
	"P2O1,User Port,Joysticks,UART;",
	"P2OQR,Pot 1&2,Joy 1 Fire 2/3,Mouse,Paddles 1&2;",
	"P2OST,Pot 3&4,Joy 2 Fire 2/3,Mouse,Paddles 3&4;",
	"P2-;",
	"P2OEF,Kernal,Loadable C64,Standard C64,C64GS,Japanese;",
	
	"-;",
	"O3,Swap Joysticks,No,Yes;",
	"-;",
	"RH,Reset;",
	"R0,Reset & Detach Cartridge;",
	"J,Fire 1,Fire 2,Fire 3,Paddle Btn;",
	"jn,A,B,Y,X|P;",
	"jp,A,B,Y,X|P;",
	"V,v",`BUILD_DATE
};


wire pll_locked;
wire clk_sys;
wire clk64;
wire clk48;

pll pll
(
	.refclk(CLK_50M),
	.outclk_0(clk48),
	.outclk_1(clk64),
	.outclk_2(clk_sys),
	.reconfig_to_pll(reconfig_to_pll),
	.reconfig_from_pll(reconfig_from_pll),
	.locked(pll_locked)
);

wire [63:0] reconfig_to_pll;
wire [63:0] reconfig_from_pll;
wire        cfg_waitrequest;
reg         cfg_write;
reg   [5:0] cfg_address;
reg  [31:0] cfg_data;

pll_cfg pll_cfg
(
	.mgmt_clk(CLK_50M),
	.mgmt_reset(0),
	.mgmt_waitrequest(cfg_waitrequest),
	.mgmt_read(0),
	.mgmt_readdata(),
	.mgmt_write(cfg_write),
	.mgmt_address(cfg_address),
	.mgmt_writedata(cfg_data),
	.reconfig_to_pll(reconfig_to_pll),
	.reconfig_from_pll(reconfig_from_pll)
);

always @(posedge CLK_50M) begin
	reg ntscd = 0, ntscd2 = 0;
	reg [2:0] state = 0;
	reg ntsc_r;

	ntscd <= ntsc;
	ntscd2 <= ntscd;

	cfg_write <= 0;
	if(ntscd2 == ntscd && ntscd2 != ntsc_r) begin
		state <= 1;
		ntsc_r <= ntscd2;
	end

	if(!cfg_waitrequest) begin
		if(state) state<=state+1'd1;
		case(state)
			1: begin
					cfg_address <= 0;
					cfg_data <= 0;
					cfg_write <= 1;
				end
				/*
			3: begin
					cfg_address <= 4;
					cfg_data <= ntsc_r ? 'h20504 : 'h404;
					cfg_write <= 1;
				end
				*/
			5: begin
					cfg_address <= 7;
					cfg_data <= ntsc_r ? 3357876127 : 1503512573;
					cfg_write <= 1;
				end
			7: begin
					cfg_address <= 2;
					cfg_data <= 0;
					cfg_write <= 1;
				end
		endcase
	end
end

reg reset_n;
always @(posedge clk_sys) begin
	integer reset_counter;

	if (status[0] | status[17] | buttons[1] | !pll_locked) begin
		reset_counter <= 100000;
		reset_n <= 0;
	end
	else if (reset_crt || (ioctl_download && load_cart)) begin
		reset_counter <= 255;
		reset_n <= 0;
	end
	else if (ioctl_download || inj_meminit);
	else if (erasing) force_erase <= 0;
	else if (!reset_counter) reset_n <= 1;
	else begin
		reset_counter <= reset_counter - 1;
		if (reset_counter == 100) force_erase <= 1;
	end
end 


wire [15:0] joyA,joyB,joyC,joyD;

wire [63:0] status;
wire        forced_scandoubler;

wire        ioctl_wr;
wire [24:0] ioctl_addr;
wire  [7:0] ioctl_data;
wire  [7:0] ioctl_index;
wire        ioctl_download;

wire [31:0] sd_lba1, sd_lba2;
wire  [1:0] sd_rd;
wire  [1:0] sd_wr;
wire  [1:0] sd_ack;
wire  [8:0] sd_buff_addr;
wire  [7:0] sd_buff_dout;
wire  [7:0] sd_buff_din1, sd_buff_din2;
wire        sd_buff_wr;
wire  [1:0] sd_change;
wire        disk_readonly;

wire [24:0] ps2_mouse;
wire [10:0] ps2_key;
wire  [1:0] buttons;
wire [21:0] gamma_bus;

wire  [7:0] pd1,pd2,pd3,pd4;

hps_io #(.STRLEN($size(CONF_STR)>>3), .VDNUM(2)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),

	.joystick_0(joyA),
	.joystick_1(joyB),
	.joystick_2(joyC),
	.joystick_3(joyD),

	.paddle_0(pd1),
	.paddle_1(pd2),
	.paddle_2(pd3),
	.paddle_3(pd4),

	.conf_str(CONF_STR),

	.status(status),
	.status_menumask({status[16],status[13],tap_loaded, en1080p, |vcrop, ~status[25]}),
	.buttons(buttons),
	.forced_scandoubler(forced_scandoubler),
	.gamma_bus(gamma_bus),

	.sd_lba((sd_rd[0]|sd_wr[0]) ? sd_lba1 : sd_lba2),
	.sd_rd(sd_rd),
	.sd_wr(sd_wr),
	.sd_ack(sd_ack),

	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(c1541_1_busy ? sd_buff_din1 : sd_buff_din2),
	.sd_buff_wr(sd_buff_wr),
	.img_mounted(sd_change),
	.img_readonly(disk_readonly),

	.ps2_key(ps2_key),
	.ps2_mouse(ps2_mouse),

	.ioctl_download(ioctl_download),
	.ioctl_index(ioctl_index),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_data),
	.ioctl_wait(ioctl_req_wr)
);

wire game;
wire exrom;
wire IOE_rom;
wire IOF_rom;
wire max_ram;
wire mem_ce;
wire nmi;
wire reset_crt;

wire [24:0] cart_addr;
wire load_cart = (ioctl_index == 5) || (ioctl_index == 'hC0);

cartridge cartridge
(
	.romL(romL),
	.romH(romH),
	.UMAXromH(UMAXromH),
	.IOE(IOE),
	.IOF(IOF),
	.mem_write(~ram_we),
	.mem_ce(~ram_ce),
	.mem_ce_out(mem_ce),

	.clk32(clk_sys),
	.reset(reset_n),
	.reset_out(reset_crt),

	.cart_id(cart_id),
	.cart_exrom(cart_exrom),
	.cart_game(cart_game),

	.cart_bank_laddr(cart_bank_laddr),
	.cart_bank_size(cart_bank_size),
	.cart_bank_num(cart_bank_num),
	.cart_bank_type(cart_bank_type),
	.cart_bank_raddr(ioctl_load_addr),
	.cart_bank_wr(cart_hdr_wr),

	.cart_attached(cart_attached),
	.cart_loading(ioctl_download && load_cart),

	.c64_mem_address_in(c64_addr),
	.c64_data_out(c64_data_out),

	.sdram_address_out(cart_addr),
	.exrom(exrom),
	.game(game),
	.IOE_ena(IOE_rom),
	.IOF_ena(IOF_rom),
	.max_ram(max_ram),
	.freeze_key(freeze_key),
	.mod_key(mod_key),
	.nmi(nmi),
	.nmi_ack(nmi_ack)
);

// rearrange joystick contacts for c64
wire [6:0] joyA_int = {joyA[6:4], joyA[0], joyA[1], joyA[2], joyA[3]};
wire [6:0] joyB_int = {joyB[6:4], joyB[0], joyB[1], joyB[2], joyB[3]};
wire [6:0] joyC_c64 = {joyC[6:4], joyC[0], joyC[1], joyC[2], joyC[3]};
wire [6:0] joyD_c64 = {joyD[6:4], joyD[0], joyD[1], joyD[2], joyD[3]};

// swap joysticks if requested
wire [6:0] joyA_c64 = status[3] ? joyB_int : joyA_int;
wire [6:0] joyB_c64 = status[3] ? joyA_int : joyB_int;

wire [7:0] paddle_1 = status[3] ? pd3 : pd1;
wire [7:0] paddle_2 = status[3] ? pd4 : pd2;
wire [7:0] paddle_3 = status[3] ? pd1 : pd3;
wire [7:0] paddle_4 = status[3] ? pd2 : pd4;

wire       paddle_1_btn = status[3] ? joyC[7] : joyA[7];
wire       paddle_2_btn = status[3] ? joyD[7] : joyB[7];
wire       paddle_3_btn = status[3] ? joyA[7] : joyC[7];
wire       paddle_4_btn = status[3] ? joyB[7] : joyD[7];

wire [1:0] pd12_mode = status[27:26];
wire [1:0] pd34_mode = status[29:28];

reg [24:0] ioctl_load_addr;
reg        ioctl_req_wr;

reg [15:0] cart_id;
reg [15:0] cart_bank_laddr;
reg [15:0] cart_bank_size;
reg [15:0] cart_bank_num;
reg  [7:0] cart_bank_type;
reg  [7:0] cart_exrom;
reg  [7:0] cart_game;
reg        cart_attached = 0;
reg  [3:0] cart_hdr_cnt;
reg        cart_hdr_wr;
reg [31:0] cart_blk_len;

reg [15:0] inj_start;
reg [15:0] inj_end;

reg        force_erase;
reg        erasing;

wire       load_inj = (ioctl_index[5:0] == 4);
wire       load_prg = (ioctl_index[7:6] == 0) && load_inj;
reg        inj_meminit = 0;
reg  [7:0] inj_meminit_data;

wire       io_cycle;
reg        io_cycle_ce;
reg        io_cycle_we;
reg [24:0] io_cycle_addr;
reg  [7:0] io_cycle_data;

localparam TAP_ADDR = 25'h200000;

always @(posedge clk_sys) begin
	reg [4:0] erase_to;
	reg old_download;
	reg erase_cram;
	reg io_cycleD;
	reg old_st0 = 0;
	reg old_meminit;

	old_download <= ioctl_download;
	io_cycleD <= io_cycle;
	cart_hdr_wr <= 0;
	old_meminit <= inj_meminit;
	
	if (~io_cycle & io_cycleD) begin
		io_cycle_ce <= 1;
		io_cycle_we <= 0;
		io_cycle_addr <= tap_play_addr + TAP_ADDR;
		if (ioctl_req_wr) begin
			ioctl_req_wr <= 0;
			io_cycle_we <= 1;
			io_cycle_addr <= ioctl_load_addr;
			ioctl_load_addr <= ioctl_load_addr + 1'b1;
			if (erasing) io_cycle_data <= {8{ioctl_load_addr[6]}};
			else if (inj_meminit) io_cycle_data <= inj_meminit_data;
			else io_cycle_data <= ioctl_data;
		end
	end

	if (io_cycle & io_cycleD) {io_cycle_ce, io_cycle_we} <= 0;

	if (ioctl_wr) begin
		if (load_inj) begin
			if (load_prg) begin
				// PRG header
				// Load address low-byte
				if      (ioctl_addr == 0) begin ioctl_load_addr[7:0]  <= ioctl_data; inj_start[7:0]  <= ioctl_data; inj_end[7:0]  <= ioctl_data; end
				// Load address high-byte
				else if (ioctl_addr == 1) begin ioctl_load_addr[15:8] <= ioctl_data; inj_start[15:8] <= ioctl_data; inj_end[15:8] <= ioctl_data; end
				else begin ioctl_req_wr <= 1; inj_end <= inj_end + 1'b1; end
			end
		end

		if (load_cart) begin
			if (ioctl_addr == 0) begin
				ioctl_load_addr <= 24'h100000;
				cart_blk_len <= 0;
				cart_hdr_cnt <= 0;
			end 

			if (ioctl_addr == 8'h16) cart_id[15:8]   <= ioctl_data;
			if (ioctl_addr == 8'h17) cart_id[7:0]    <= ioctl_data;
			if (ioctl_addr == 8'h18) cart_exrom[7:0] <= ioctl_data;
			if (ioctl_addr == 8'h19) cart_game[7:0]  <= ioctl_data;

			if (ioctl_addr >= 8'h40) begin
				if (cart_blk_len == 0 & cart_hdr_cnt == 0) begin
					cart_hdr_cnt <= 1;
					if (ioctl_load_addr[12:0] != 0) begin
						// align to 8KB boundary
						ioctl_load_addr[12:0] <= 0;
						ioctl_load_addr[24:13] <= ioctl_load_addr[24:13] + 1'b1;
					end
				end else if (cart_hdr_cnt != 0) begin
					cart_hdr_cnt <= cart_hdr_cnt + 1'b1;
					if (cart_hdr_cnt == 4)  cart_blk_len[31:24]  <= ioctl_data;
					if (cart_hdr_cnt == 5)  cart_blk_len[23:16]  <= ioctl_data;
					if (cart_hdr_cnt == 6)  cart_blk_len[15:8]   <= ioctl_data;
					if (cart_hdr_cnt == 7)  cart_blk_len[7:0]    <= ioctl_data;
					if (cart_hdr_cnt == 8)  cart_blk_len         <= cart_blk_len - 8'h10;
					if (cart_hdr_cnt == 9)  cart_bank_type       <= ioctl_data;
					if (cart_hdr_cnt == 10) cart_bank_num[15:8]  <= ioctl_data;
					if (cart_hdr_cnt == 11) cart_bank_num[7:0]   <= ioctl_data;
					if (cart_hdr_cnt == 12) cart_bank_laddr[15:8]<= ioctl_data;
					if (cart_hdr_cnt == 13) cart_bank_laddr[7:0] <= ioctl_data;
					if (cart_hdr_cnt == 14) cart_bank_size[15:8] <= ioctl_data;
					if (cart_hdr_cnt == 15) cart_bank_size[7:0]  <= ioctl_data;
					if (cart_hdr_cnt == 15) cart_hdr_wr <= 1;
				end
				else begin
					cart_blk_len <= cart_blk_len - 1'b1;
					ioctl_req_wr <= 1;
				end
			end
		end
		
		if (load_tap) begin
			if (ioctl_addr == 0) ioctl_load_addr <= TAP_ADDR;
			ioctl_req_wr <= 1;
		end
	end
	
	if (old_download != ioctl_download && load_cart) begin
		cart_attached <= old_download;
		erase_cram <= 1;
	end 

	// meminit for RAM injection
	if (old_download != ioctl_download && load_inj && !inj_meminit) begin
		inj_meminit <= 1;
		ioctl_load_addr <= 0;
	end

	if (inj_meminit) begin
		if (!ioctl_req_wr) begin
			// check if done
			if (ioctl_load_addr == 'h100) begin
				inj_meminit <= 0;
			end
			else begin
				ioctl_req_wr <= 1;
				
				// Initialize BASIC pointers to simulate the BASIC LOAD command
				case(ioctl_load_addr)
					// TXT (2B-2C)
					// Set these two bytes to $01, $08 just as they would be on reset (the BASIC LOAD command does not alter these)
					'h2B: inj_meminit_data <= 'h01;
					'h2C: inj_meminit_data <= 'h08;

					// SAVE_START (AC-AD)
					// Set these two bytes to zero just as they would be on reset (the BASIC LOAD command does not alter these)
					'hAC, 'hAD: inj_meminit_data <= 'h00;
					
					// VAR (2D-2E), ARY (2F-30), STR (31-32), LOAD_END (AE-AF)
					// Set these just as they would be with the BASIC LOAD command (essentially they are all set to the load end address)
					'h2D, 'h2F, 'h31, 'hAE: inj_meminit_data <= inj_end[7:0];
					'h2E, 'h30, 'h32, 'hAF: inj_meminit_data <= inj_end[15:8];
					
					default: begin
						ioctl_req_wr <= 0;
						
						// advance the address
						ioctl_load_addr <= ioctl_load_addr + 1'b1;
					end
				endcase
			end
		end
	end

	start_strk <= (old_meminit && !inj_meminit);
	
	old_st0 <= status[0];
	if (~old_st0 & status[0]) cart_attached <= 0;
	
	if (!erasing && force_erase) begin
		erasing <= 1;
		ioctl_load_addr <= 0;
	end

	if (erasing && !ioctl_req_wr) begin
		erase_to <= erase_to + 1'b1;
		if (&erase_to) begin
			if (ioctl_load_addr < ({erase_cram, 16'hFFFF}))
				ioctl_req_wr <= 1;
			else begin
				erasing <= 0;
				erase_cram <= 0;
			end
		end
	end
end

reg start_strk = 0;
reg [10:0] key = 0;
always @(posedge clk_sys) begin
	reg [3:0] act = 0;
	int to;

	if(~reset_n) act <= 0;
	if(act) begin
		to <= to + 1;
		if(to > 1280000) begin
			to <= 0;
			act <= act + 1'd1;
			case(act)
				// PS/2 scan codes
				1:  key <= 'h12;
				2:  key <= 'h5a;  // make sure enter is released (sometimes got captured)
				3:  key <= 'h6c;  // <HOME/CLR> instead of ending with ":" so not to break compatibility (eg "a mind is born")
				5:  key <= 'h12;  // release shift
				7:  key <= 'h2d;  // R
				9:  key <= 'h3c;  // U
				11: key <= 'h31;  // N
				13: key <= 'h5a;  // <RETURN>
				15: act <= 0;
			endcase
			key[9] <= act[0];
			key[10] <= ~key[10];
		end
	end
	else begin
		to <= 0;
		key <= ps2_key;
	end
	if(start_strk) act <= 1;
end

assign SDRAM_CKE  = 1;
assign SDRAM_DQML = 0;
assign SDRAM_DQMH = 0;

wire [7:0] sdram_data;
sdram sdram
(
	.sd_addr(SDRAM_A),
	.sd_data(SDRAM_DQ),
	.sd_ba(SDRAM_BA),
	.sd_cs(SDRAM_nCS),
	.sd_we(SDRAM_nWE),
	.sd_ras(SDRAM_nRAS),
	.sd_cas(SDRAM_nCAS),
	.sd_clk(SDRAM_CLK),

	.clk(clk64),
	.init(~pll_locked),
	.refresh(idle),
	.addr( io_cycle ? io_cycle_addr : cart_addr    ),
	.ce  ( io_cycle ? io_cycle_ce   : mem_ce       ),
	.we  ( io_cycle ? io_cycle_we   : ~ram_we      ),
	.din ( io_cycle ? io_cycle_data : c64_data_out ),
	.dout( sdram_data )
);

wire  [7:0] c64_data_out;
wire [15:0] c64_addr;
wire        idle;
wire        ram_ce;
wire        ram_we;
wire        nmi_ack;
wire        freeze_key;
wire        mod_key;

wire        IOE;
wire        IOF;
wire        romL;
wire        romH;
wire        UMAXromH;

wire        sid_we;
wire [17:0] audio_l,audio_r;
wire  [7:0] r,g,b;

wire        ntsc = status[2];

fpga64_sid_iec fpga64
(
	.clk32(clk_sys),
	.reset_n(reset_n),
	.bios(status[15:14]),
	.ps2_key(key),
	.ramaddr(c64_addr),
	.ramdataout(c64_data_out),
	.ramdatain(sdram_data),
	.ramce(ram_ce),
	.ramwe(ram_we),
	.ntscmode(ntsc),
	.hsync(hsync),
	.vsync(vsync),
	.r(r),
	.g(g),
	.b(b),
	.game(game),
	.exrom(exrom),
	.ioe_rom(IOE_rom),
	.iof_rom(IOF_rom),
	.max_ram(max_ram),
	.umaxromh(UMAXromH),
	.cpu_hasbus(),
	.irq_n(1),
	.nmi_n(~nmi),
	.nmi_ack(nmi_ack),
	.freeze_key(freeze_key),
	.mod_key(mod_key),
	.dma_n(1'b1),
	.roml(romL),
	.romh(romH),
	.ioe(IOE),
	.iof(IOF),
	.iof_ext(opl_en),
	.ioe_ext(1'b0),
	.io_data(sid2_oe ? data_sid : opl_dout),

	.joya(joyA_c64 | {1'b0, pd12_mode[1] & paddle_2_btn, pd12_mode[1] & paddle_1_btn, 2'b00} | {pd12_mode[0] & mouse_btn[0], 3'b000, pd12_mode[0] & mouse_btn[1]}),
	.joyb(joyB_c64 | {1'b0, pd34_mode[1] & paddle_4_btn, pd34_mode[1] & paddle_3_btn, 2'b00} | {pd34_mode[0] & mouse_btn[0], 3'b000, pd34_mode[0] & mouse_btn[1]}),
	.joyc(joyC_c64),
	.joyd(joyD_c64),

	.pot1(pd12_mode[1] ? paddle_1 : pd12_mode[0] ? mouse_x : {8{joyA_c64[5]}}),
	.pot2(pd12_mode[1] ? paddle_2 : pd12_mode[0] ? mouse_y : {8{joyA_c64[6]}}),
	.pot3(pd34_mode[1] ? paddle_3 : pd34_mode[0] ? mouse_x : {8{joyB_c64[5]}}),
	.pot4(pd34_mode[1] ? paddle_4 : pd34_mode[0] ? mouse_y : {8{joyB_c64[6]}}),

	.io_cycle(io_cycle),
	.idle(idle),
	.sid_we_ext(sid_we),
	.sid_mode({status[22:21]==1,status[20]}),
	.sid_cfg(status[35:34]),
	.sid_ld_clk(clk_sys),
	.sid_ld_addr(sid_ld_addr),
	.sid_ld_data(sid_ld_data),
	.sid_ld_wr(sid_ld_wr),
	
	.audio_data(audio_l),
	.sid_filter(1),
	.sid_ver(status[13]),
	.iec_data_o(c64_iec_data),
	.iec_atn_o(c64_iec_atn),
	.iec_clk_o(c64_iec_clk),
	.iec_data_i(c64_iec_data_i),
	.iec_clk_i(c64_iec_clk_i),
	.c64rom_addr(ioctl_addr[13:0]),
	.c64rom_data(ioctl_data),
	.c64rom_wr((ioctl_index == 0) && !ioctl_addr[14] && ioctl_download && ioctl_wr),

	.cass_motor(cass_motor),
	.cass_sense(~tap_play),
	.cass_in(cass_do),

	.uart_enable(status[1]),
	.uart_txd(UART_TXD),
	.uart_rts(!UART_RTS), // Trying inverting these, as I think they are breaking minicom and other terminal programs on the HPS? ElectronAsh.
	.uart_dtr(!UART_DTR),
	.uart_ri_out(),
	.uart_dcd_out(),
	.uart_rxd(UART_RXD),
	.uart_ri_in(1),	    // I think these are active-High on the User Port? (even those TXD and RXD seem to be active-low.) ElectronAsh.
	.uart_dcd_in(1),
	.uart_cts(1),
	.uart_dsr(1)
);

wire [7:0] mouse_x;
wire [7:0] mouse_y;
wire [1:0] mouse_btn;

c1351 mouse
(
	.clk_sys(clk_sys),
	.reset(~reset_n),

	.ps2_mouse(ps2_mouse),
	
	.potX(mouse_x),
	.potY(mouse_y),
	.button(mouse_btn)
);

wire drive9 = status[25];

reg c64_iec_data_i, c64_iec_clk_i;
always @(posedge clk_sys) begin
	reg iec_data_d1, iec_clk_d1;
	reg iec_data_d2, iec_clk_d2;

	iec_data_d1 <= c1541_1_iec_data & (~drive9 | c1541_2_iec_data);
	iec_data_d2 <= iec_data_d1;
	if(iec_data_d1 == iec_data_d2) c64_iec_data_i <= iec_data_d2;

	iec_clk_d1 <= c1541_1_iec_clk & (~drive9 | c1541_2_iec_clk);
	iec_clk_d2 <= iec_clk_d1;
	if(iec_clk_d1 == iec_clk_d2) c64_iec_clk_i <= iec_clk_d2;
end

wire c64_iec_clk;
wire c64_iec_data;
wire c64_iec_atn;

wire c1541_reset = ~reset_n | status[6];

wire c1541_1_iec_clk;
wire c1541_1_iec_data;
wire c1541_1_led;
wire c1541_1_busy;

c1541_sd c1541_1
(
	.clk_c1541(clk64 & ce_c1541),
	.clk_sys(clk_sys),

	.rom_addr(ioctl_addr[13:0]),
	.rom_data(ioctl_data),
	.rom_wr((ioctl_index == 0) &&  ioctl_addr[14] && ioctl_download && ioctl_wr),
	.rom_std(status[14]),

	.disk_change(sd_change[0]),
	.disk_readonly(disk_readonly),
	.drive_num(0),

	.iec_atn_i(c64_iec_atn),
	.iec_data_i(c64_iec_data),
	.iec_clk_i(c64_iec_clk),
	.iec_data_o(c1541_1_iec_data),
	.iec_clk_o(c1541_1_iec_clk),
	.iec_reset_i(c1541_reset),

	.sd_lba(sd_lba1),
	.sd_rd(sd_rd[0]),
	.sd_wr(sd_wr[0]),
	.sd_ack(sd_ack[0]),
	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(sd_buff_din1),
	.sd_buff_wr(sd_buff_wr),
	.sd_busy(c1541_1_busy),

	.led(c1541_1_led)
);

wire c1541_2_iec_clk;
wire c1541_2_iec_data;
wire c1541_2_led;

c1541_sd c1541_2
(
	.clk_c1541(clk64 & ce_c1541),
	.clk_sys(clk_sys),

	.rom_addr(ioctl_addr[13:0]),
	.rom_data(ioctl_data),
	.rom_wr((ioctl_index == 0) &&  ioctl_addr[14] && ioctl_download && ioctl_wr),
	.rom_std(status[14]),

	.disk_change(sd_change[1]),
	.disk_readonly(disk_readonly),
	.drive_num(1),

	.iec_atn_i(c64_iec_atn | ~drive9),
	.iec_data_i(c64_iec_data | ~drive9),
	.iec_clk_i(c64_iec_clk | ~drive9),
	.iec_data_o(c1541_2_iec_data),
	.iec_clk_o(c1541_2_iec_clk),
	.iec_reset_i(c1541_reset),

	.sd_lba(sd_lba2),
	.sd_rd(sd_rd[1]),
	.sd_wr(sd_wr[1]),
	.sd_ack(sd_ack[1]),
	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(sd_buff_din2),
	.sd_buff_wr(sd_buff_wr),

	.led(c1541_2_led)
);

reg ce_c1541;
always @(negedge clk64) begin
	int sum = 0;
	int msum;
	
	msum <= ntsc ? 65454537 : 63055911;

	ce_c1541 <= 0;
	sum = sum + 32000000;
	if(sum >= msum) begin
		sum = sum - msum;
		ce_c1541 <= 1;
	end
end


wire hsync;
wire vsync;
wire hblank;
wire vblank;
wire hsync_out;
wire vsync_out;

video_sync sync
(
	.clk32(clk_sys),
	.hsync(hsync),
	.vsync(vsync),
	.ntsc(ntsc),
	.wide(wide),
	.hsync_out(hsync_out),
	.vsync_out(vsync_out),
	.hblank(hblank),
	.vblank(vblank)
);

reg hq2x160;
always @(posedge clk_sys) begin
	reg old_vsync;

	old_vsync <= vsync_out;
	if (!old_vsync && vsync_out) begin
		hq2x160 <= (status[10:8] == 2);
	end
end

reg ce_pix;
always @(posedge CLK_VIDEO) begin
	reg [2:0] div;
	reg       lores;

	div <= div + 1'b1;
	if(&div) lores <= ~lores;
	ce_pix <= (~lores | ~hq2x160) && !div;
end

wire scandoubler = status[10:8] || forced_scandoubler;

assign CLK_VIDEO = clk64;
assign VGA_SL    = (status[10:8] > 2) ? status[9:8] - 2'd2 : 2'd0;
assign VGA_F1    = 0;

reg [9:0] vcrop;
reg wide;
always @(posedge CLK_VIDEO) begin
	vcrop <= 0;
	wide <= 0;
	if(HDMI_WIDTH >= (HDMI_HEIGHT + HDMI_HEIGHT[11:1]) && !scandoubler) begin
		if(HDMI_HEIGHT == 480)  vcrop <= 240;
		if(HDMI_HEIGHT == 600)  begin vcrop <= 200; wide <= vcrop_en; end
		if(HDMI_HEIGHT == 720)  vcrop <= 240;
		if(HDMI_HEIGHT == 768)  vcrop <= 256; // NTSC mode has 250 visible lines only!
		if(HDMI_HEIGHT == 800)  begin vcrop <= 200; wide <= vcrop_en; end
		if(HDMI_HEIGHT == 1080) vcrop <= (ntsc | status[33]) ? 10'd216 : 10'd270;
		if(HDMI_HEIGHT == 1200) vcrop <= 240;
	end
end

reg en1080p;
always @(posedge CLK_VIDEO) en1080p <= (HDMI_WIDTH == 1920) && (HDMI_HEIGHT == 1080);


wire [1:0] ar = status[5:4];
wire vcrop_en = en1080p ? |status[33:32] : status[32];
wire vga_de;
video_freak video_freak
(
	.*,
	.VGA_DE_IN(vga_de),
	.ARX((!ar) ? (wide ? 12'd340 : 12'd400) : (ar - 1'd1)),
	.ARY((!ar) ? 12'd300 : 12'd0),
	.CROP_SIZE(vcrop_en ? vcrop : 10'd0),
	.CROP_OFF(0),
	.SCALE(status[31:30])
);

video_mixer #(.GAMMA(1)) video_mixer
(
	.CLK_VIDEO(CLK_VIDEO),

	.hq2x(~status[10] & (status[9] ^ status[8])),
	.scandoubler(scandoubler),
	.gamma_bus(gamma_bus),

	.ce_pix(ce_pix),
	.R(r),
	.G(g),
	.B(b),
	.HSync(hsync_out),
	.VSync(vsync_out),
	.HBlank(hblank),
	.VBlank(vblank),

	.CE_PIXEL(CE_PIXEL),
	.VGA_R(VGA_R),
	.VGA_G(VGA_G),
	.VGA_B(VGA_B),
	.VGA_VS(VGA_VS),
	.VGA_HS(VGA_HS),
	.VGA_DE(vga_de)
);

wire        opl_en = status[12];
wire [15:0] opl_out;
wire  [7:0] opl_dout;
opl3 #(.OPLCLK(47291931)) opl_inst
(
	.clk(clk_sys),
	.clk_opl(clk48),
	.rst_n(reset_n & opl_en),

	.addr(c64_addr[4]),
	.dout(opl_dout),
	.we(~ram_we & IOF & opl_en & c64_addr[6] & ~c64_addr[5]),
	.din(c64_data_out),

	.sample_l(opl_out)
);

reg [31:0] ce_1m;
always @(posedge clk_sys) ce_1m <= reset_n ? {ce_1m[30:0], ce_1m[31]} : 1;

reg ioe_we, iof_we;
always @(posedge clk_sys) begin
	reg old_ioe, old_iof;

	old_ioe <= IOE;
	ioe_we <= ~old_ioe & IOE & ~ram_we;

	old_iof <= IOF;
	iof_we <= ~old_iof & IOF & ~ram_we;
end

wire sid2_we = (status[22:20]==1) ? ioe_we : (status[22:20]==4) ? iof_we : sid_we;
wire sid2_oe = (status[22:20]==1) ? IOE    : (status[22:20]==4) ? IOF    : ~IOE & ~IOF;

reg [11:0] sid_ld_addr = 0;
reg [15:0] sid_ld_data = 0;
reg        sid_ld_wr   = 0;
always @(posedge clk_sys) begin
	sid_ld_wr <= 0;
	if(ioctl_wr && ioctl_index == 7 && ioctl_addr < 6144) begin
		if(ioctl_addr[0]) begin
			sid_ld_data[15:8] <= ioctl_data;
			sid_ld_addr <= ioctl_addr[12:1];
			sid_ld_wr <= 1;
		end
		else begin
			sid_ld_data[7:0] <= ioctl_data;
		end
	end
end

wire  [7:0] data_sid;
sid_top sid
(
	.clk(clk_sys),
	.reset(~reset_n),
	.ce_1m(ce_1m[31]),

	.addr(c64_addr[4:0]),
	.we(sid2_we),
	.data_in(c64_data_out),
	.data_out(data_sid),

	.audio_data(audio_r),

	.filter_en(1),
	.cfg(status[38:37]),
	.mode(status[16]),

	.ld_clk(clk_sys),
	.ld_addr(sid_ld_addr),
	.ld_data(sid_ld_data),
	.ld_wr(sid_ld_wr)
);

//DigiMax
reg [8:0] dac_l, dac_r;
always @(posedge clk_sys) begin
	reg [8:0] dac[4];
	reg [3:0] act;

	if(!status[41:40] || ~reset_n) begin
		dac <= '{0,0,0,0};
		act <= 0;
	end
	else if((status[41] ? iof_we : ioe_we) && ~c64_addr[2]) begin
		dac[c64_addr[1:0]] <= c64_data_out;
		if(c64_data_out) act[c64_addr[1:0]] <= 1;
	end

	// guess mono/stereo/4-chan modes
	if(act<2) begin
		dac_l <= dac[0] + dac[0];
		dac_r <= dac[0] + dac[0];
	end
	else if(act<3) begin
		dac_l <= dac[1] + dac[1];
		dac_r <= dac[0] + dac[0];
	end
	else begin
		dac_l <= dac[1] + dac[2];
		dac_r <= dac[0] + dac[3];
	end
end

localparam [3:0] comp_f1 = 4;
localparam [3:0] comp_a1 = 2;
localparam       comp_x1 = ((32767 * (comp_f1 - 1)) / ((comp_f1 * comp_a1) - 1)) + 1; // +1 to make sure it won't overflow
localparam       comp_b1 = comp_x1 * comp_a1;

function [15:0] compr; input [15:0] inp;
	reg [15:0] v, v1;
	begin
		v  = inp[15] ? (~inp) + 1'd1 : inp;
		v1 = (v < comp_x1[15:0]) ? (v * comp_a1) : (((v - comp_x1[15:0])/comp_f1) + comp_b1[15:0]);
		v  = v1;
		compr = inp[15] ? ~(v-1'd1) : v;
	end
endfunction

reg [15:0] alo,aro;
always @(posedge clk_sys) begin
	reg [16:0] alm,arm;
	reg [15:0] cout;
	reg [15:0] cin;
	
	cin  <= opl_out - {{3{opl_out[15]}},opl_out[15:3]};
	cout <= compr(cin);

	alm <= {cout[15],cout} + {audio_l[17],audio_l[17:2]} + {2'b0,dac_l,6'd0} + {cass_snd, 10'd0};
	arm <= {cout[15],cout} + {audio_r[17],audio_r[17:2]} + {2'b0,dac_r,6'd0} + {cass_snd, 10'd0};
	alo <= ^alm[16:15] ? {alm[16], {15{alm[15]}}} : alm[15:0];
	aro <= ^arm[16:15] ? {arm[16], {15{arm[15]}}} : arm[15:0];
end

assign AUDIO_L = alo;
assign AUDIO_R = aro;
assign AUDIO_S = 1;
assign AUDIO_MIX = status[19:18];

//------------- TAP -------------------

reg [24:0] tap_play_addr;
reg [24:0] tap_last_addr;
wire       tap_reset = ~reset_n | tape_download | status[23] | (cass_motor & ((tap_last_addr - tap_play_addr) < 80));
reg        tap_wrreq;
wire       tap_wrfull;
wire       tap_finish;
wire       tap_loaded = (tap_play_addr < tap_last_addr);
reg        tap_play;
wire       tap_play_btn = status[7];

wire       load_tap = (ioctl_index == 6);
wire       tape_download = ioctl_download & load_tap;

always @(posedge clk_sys) begin
	reg io_cycleD, tap_finishD;
	reg read_cyc;
	reg tap_play_btnD;

	tap_play_btnD <= tap_play_btn;
	io_cycleD <= io_cycle;
	tap_finishD <= tap_finish;
	tap_wrreq <= 0;

	if(tap_reset) begin
		//C1530 module requires one more byte at the end due to fifo early check.
		tap_last_addr <= tape_download ? ioctl_addr+2'd2 : 25'd0;
		tap_play_addr <= 0;
		tap_play <= tape_download;
		read_cyc <= 0;
	end
	else begin
		if (~tap_play_btnD & tap_play_btn) tap_play <= ~tap_play;
		if (~tap_finishD & tap_finish) tap_play <= 0;

		if (~io_cycle & io_cycleD & ~tap_wrfull & tap_loaded) read_cyc <= 1;
		if (io_cycle & io_cycleD & read_cyc) begin
			tap_play_addr <= tap_play_addr + 1'd1;
			read_cyc <= 0;
			tap_wrreq <= 1;
		end
	end
end

reg [26:0] act_cnt;
always @(posedge clk_sys) act_cnt <= act_cnt + (tap_play ? 4'd8 : 4'd1);
wire tape_led = tap_loaded && (act_cnt[26] ? (~(tap_play & cass_motor) && act_cnt[25:18] > act_cnt[7:0]) : act_cnt[25:18] <= act_cnt[7:0]);

wire cass_motor;
wire cass_run = ~cass_motor & tap_play;
wire cass_snd = cass_run & status[11] & cass_do;
wire cass_do;

c1530 c1530
(
	.clk(clk_sys),
	.restart(tap_reset),

	.clk_freq(32000000),
	.cpu_freq(1000000),

	.din(sdram_data),
	.wr(tap_wrreq),
	.full(tap_wrfull),
	.empty(tap_finish),

	.play(cass_run),
	.dout(cass_do)
);

endmodule
