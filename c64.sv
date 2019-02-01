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
	inout  [44:0] HPS_BUS,

	//Base video clock. Usually equals to CLK_SYS.
	output        CLK_VIDEO,

	//Multiple resolutions are supported using different CE_PIXEL rates.
	//Must be based on CLK_VIDEO
	output        CE_PIXEL,

	//Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
	output  [7:0] VIDEO_ARX,
	output  [7:0] VIDEO_ARY,

	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_DE,    // = ~(VBlank | HBlank)
	output        VGA_F1,
	output [1:0]  VGA_SL,

	output        LED_USER,  // 1 - ON, 0 - OFF.

	// b[1]: 0 - LED status is system status OR'd with b[0]
	//       1 - LED status is controled solely by b[0]
	// hint: supply 2'b00 to let the system control the LED.
	output  [1:0] LED_POWER,
	output  [1:0] LED_DISK,

	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R,
	output        AUDIO_S,   // 1 - signed audio samples, 0 - unsigned
	output  [1:0] AUDIO_MIX, // 0 - no mix, 1 - 25%, 2 - 50%, 3 - 100% (mono)
	input         TAPE_IN,

	// SD-SPI
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

	input         UART_CTS,
	output        UART_RTS,
	input         UART_RXD,
	output        UART_TXD,
	output        UART_DTR,
	input         UART_DSR,

	input         OSD_STATUS
);

assign {DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_DIN, DDRAM_BE, DDRAM_RD, DDRAM_WE} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;

assign LED_DISK = 0;
assign LED_POWER = 0;

`include "build_id.v"
localparam CONF_STR = {
	"C64;;",
	"S,D64,Mount Disk;",
	"F,PRG,Load File;",
	"F,CRT,Load Cartridge;",
	"-;",
	"O2,Video standard,PAL,NTSC;",
	"O45,Aspect ratio,Original,Wide,Zoom;",
	"O8A,Scandoubler Fx,None,HQ2x-320,HQ2x-160,CRT 25%,CRT 50%,CRT 75%;",
	"-;",
	"OD,SID left,6581,8580;",
	"OG,SID right,6581,8580;",
	"OH,SID right address,Same,DE00;",
	"O6,Audio filter,On,Off;",
	"OC,Sound expander,No,OPL2;",
	"OIJ,Stereo mix,none,25%,50%,100%;",
	"-;",
	"O3,Primary joystick,Port 2,Port 1;",
	"-;",
	"OEF,Kernal,Loadable C64,Standard C64,C64GS;",
	"R0,Reset & Detach cartridge;",
	"J,Button 1,Button 2,Button 3;",
	"V,v",`BUILD_DATE
};
   

wire pll_locked;
wire clk32;
wire clk64;

pll pll
(
	.refclk(CLK_50M),
	.outclk_0(clk64),
	.outclk_1(SDRAM_CLK),
	.outclk_2(clk32),
	.locked(pll_locked)
);

reg reset_n;
always @(posedge clk32) begin
	integer reset_counter;

	if (status[0] | buttons[1] | !pll_locked) begin
		reset_counter <= 100000;
		reset_n <= 0;
	end
	else if (reset_key || reset_crt || ioctl_download && ioctl_index == 3) begin
		reset_counter <= 255;
		reset_n <= 0;
	end
	else if (ioctl_download);
	else if (erasing) force_erase <= 0;
	else if (!reset_counter) reset_n <= 1;
	else begin
		reset_counter <= reset_counter - 1;
		if (reset_counter == 100) force_erase <= 1;
	end
end 


wire [15:0] joyA,joyB,joyC,joyD;

wire [31:0] status;
wire        forced_scandoubler;

wire        ioctl_wr;
wire [24:0] ioctl_addr;
wire  [7:0] ioctl_data;
wire  [7:0] ioctl_index;
wire        ioctl_download;

wire [31:0] sd_lba;
wire        sd_rd;
wire        sd_wr;
wire        sd_ack;
wire  [8:0] sd_buff_addr;
wire  [7:0] sd_buff_dout;
wire  [7:0] sd_buff_din;
wire        sd_buff_wr;
wire        sd_change;
wire        disk_readonly;

wire [10:0] ps2_key;
wire  [1:0] buttons;

hps_io #(.STRLEN($size(CONF_STR)>>3)) hps_io
(
	.clk_sys(clk32),
	.HPS_BUS(HPS_BUS),

	.joystick_0(joyA),
	.joystick_1(joyB),
	.joystick_2(joyC),
	.joystick_3(joyD),

	.conf_str(CONF_STR),

	.status(status),
	.buttons(buttons),
	.forced_scandoubler(forced_scandoubler),

	.sd_lba(sd_lba),
	.sd_rd(sd_rd),
	.sd_wr(sd_wr),
	.sd_ack(sd_ack),

	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(sd_buff_din),
	.sd_buff_wr(sd_buff_wr),
	.img_mounted(sd_change),
	.img_readonly(disk_readonly),

	.ps2_key(ps2_key),

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

	.clk32(clk32),
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
	.cart_loading(ioctl_download && ioctl_index == 3),

	.c64_mem_address_in(c64_addr),
	.c64_data_out(c64_data_out),

	.sdram_address_out(cart_addr),
	.exrom(exrom),
	.game(game),
	.IOE_ena(IOE_rom),
	.IOF_ena(IOF_rom),
	.max_ram(max_ram),
	.freeze_key(freeze_key),
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


reg [24:0] ioctl_ram_addr;
reg  [7:0] ioctl_ram_data;
reg [24:0] ioctl_load_addr;
reg        ioctl_req_wr;
reg        ioctl_iec_cycle_used;

reg [15:0] cart_id;
reg [15:0] cart_bank_laddr;
reg [15:0] cart_bank_size;
reg [15:0] cart_bank_num;
reg  [7:0] cart_bank_type;
reg  [7:0] cart_exrom;
reg  [7:0] cart_game;
reg        cart_attached;
reg  [3:0] cart_hdr_cnt;
reg        cart_hdr_wr;
reg [31:0] cart_blk_len;

reg        force_erase;
reg        erasing;

wire       iec_cycle = (ces == 4'b1011);

always @(negedge clk32) begin
	reg [4:0] erase_to;
	reg old_download;
	reg erase_cram;
	reg iec_cycleD;

	old_download <= ioctl_download;
	iec_cycleD <= iec_cycle;
	cart_hdr_wr <= 0;
	
	if (iec_cycle & ~iec_cycleD & ioctl_req_wr) begin
		ioctl_req_wr <= 0;
		ioctl_iec_cycle_used <= 1;
		ioctl_ram_addr <= ioctl_load_addr;
		ioctl_load_addr <= ioctl_load_addr + 1'b1;
		if (erasing) ioctl_ram_data <= 0;
		else ioctl_ram_data <= ioctl_data;
	end
	else begin
		if (!iec_cycle) ioctl_iec_cycle_used <= 0;
	end

	if (ioctl_wr) begin
		if (ioctl_index == 2) begin
			if (ioctl_addr == 0) ioctl_load_addr[7:0] <= ioctl_data;
			else if (ioctl_addr == 1) ioctl_load_addr[15:8] <= ioctl_data;
			else ioctl_req_wr <= 1;
		end

		if (ioctl_index == 3) begin
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
	end
	
	if (old_download != ioctl_download & ioctl_index == 3) begin
		cart_attached <= old_download;
		erase_cram <= 1;
	end 
	
	if (status[0] | buttons[1]) cart_attached <= 0;
	
	if (!erasing && force_erase) begin
		erasing <= 1;
		ioctl_load_addr <= 0;
	end 
	
	if (erasing && !ioctl_req_wr) begin
		erase_to <= erase_to + 1'b1;
		if (erase_to == 5'b11111) begin
			if (ioctl_load_addr < ({erase_cram, 16'hFFFF}))
				ioctl_req_wr <= 1;
			else begin
				erasing <= 0;
				erase_cram <= 0;
			end
		end 
	end 
end


assign SDRAM_CKE  = 1;
assign SDRAM_DQML = 0;
assign SDRAM_DQMH = 0;
assign SDRAM_DQ   = sdram_we ? {8'd0, sdram_data_out} : 'Z;

wire        sdram_ce = (!iec_cycle) ?  mem_ce : ioctl_iec_cycle_used;
wire        sdram_we = (!iec_cycle) ? ~ram_we : ioctl_iec_cycle_used;
wire [24:0] sdram_addr     = (!iec_cycle) ? cart_addr    : ioctl_ram_addr;
wire  [7:0] sdram_data_out = (!iec_cycle) ? c64_data_out : ioctl_ram_data;

sdram sdr
(
	.sd_addr(SDRAM_A),
	.sd_ba(SDRAM_BA),
	.sd_cs(SDRAM_nCS),
	.sd_we(SDRAM_nWE),
	.sd_ras(SDRAM_nRAS),
	.sd_cas(SDRAM_nCAS),
	
	.clk(clk64),
	.addr(sdram_addr),
	.init(~pll_locked),
	.we(sdram_we),
	.refresh(idle), // refresh ram in idle state
	.ce(sdram_ce)
);


wire  [7:0] c64_data_out;
wire [15:0] c64_addr;
wire        idle;
wire  [3:0] ces;
wire        ram_ce;
wire        ram_we;
wire        nmi_ack;
wire        reset_key;
wire        freeze_key;

wire        IOE;
wire        IOF;
wire        romL;
wire        romH;
wire        UMAXromH;

wire        sid_we;
wire [17:0] audio_l;
wire  [7:0] r,g,b;

fpga64_sid_iec fpga64
(
	.clk32(clk32),
	.reset_n(reset_n),
	.bios(status[15:14]),
	.ps2_key(ps2_key),
	.ramaddr(c64_addr),
	.ramdataout(c64_data_out),
	.ramdatain(SDRAM_DQ[7:0]),
	.ramce(ram_ce),
	.ramwe(ram_we),
	.ntscmode(status[2]),
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
	.dma_n(1'b1),
	.roml(romL),
	.romh(romH),
	.ioe(IOE),
	.iof(IOF),
	.iof_ext(opl_en),
	.ioe_ext(1'b0),
	.io_data(IOF ? opl_dout : status[16] ? data_8580 : data_6581),
	.joya(joyA_c64),
	.joyb(joyB_c64),
	.joyc(joyC_c64),
	.joyd(joyD_c64),
	.ces(ces),
	.idle(idle),
	.sid_we(sid_we),
	.audio_data(audio_l),
	.extfilter_en(~status[6]),
	.sid_ver(status[13]),
	.iec_data_o(c64_iec_data),
	.iec_atn_o(c64_iec_atn),
	.iec_clk_o(c64_iec_clk),
	.iec_data_i(c1541_iec_data),
	.iec_clk_i(c1541_iec_clk),
	.c64rom_addr(ioctl_addr[13:0]),
	.c64rom_data(ioctl_data),
	.c64rom_wr((ioctl_index == 0) && !ioctl_addr[14] && ioctl_download && ioctl_wr),
	.reset_key(reset_key)
);

wire c64_iec_clk;
wire c64_iec_data;
wire c64_iec_atn;
wire c1541_iec_clk;
wire c1541_iec_data;

c1541_sd c1541
(
	.clk32(clk32),

	.c1541rom_clk(clk32),
	.c1541rom_addr(ioctl_addr[13:0]),
	.c1541rom_data(ioctl_data),
	.c1541rom_wr((ioctl_index == 0) &&  ioctl_addr[14] && ioctl_download && ioctl_wr),

	.disk_change(sd_change),
	.disk_readonly(disk_readonly),

	.iec_atn_i(c64_iec_atn),
	.iec_data_i(c64_iec_data),
	.iec_clk_i(c64_iec_clk),
	.iec_data_o(c1541_iec_data),
	.iec_clk_o(c1541_iec_clk),
	.iec_reset_i(~reset_n),

	.sd_lba(sd_lba),
	.sd_rd(sd_rd),
	.sd_wr(sd_wr),
	.sd_ack(sd_ack),
	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(sd_buff_din),
	.sd_buff_wr(sd_buff_wr),

	.led(LED_USER)
);

wire hsync;
wire vsync;
wire hblank;
wire vblank;
wire hsync_out;
wire vsync_out;

video_sync sync
(
	.clk32(clk32),
	.hsync(hsync),
	.vsync(vsync),
	.ntsc(status[2]),
	.wide(status[5]),
	.hsync_out(hsync_out),
	.vsync_out(vsync_out),
	.hblank(hblank),
	.vblank(vblank)
);

reg hq2x160;
always @(posedge clk32) begin
	reg old_vsync;

	old_vsync <= vsync_out;
	if (!old_vsync && vsync_out) begin
		hq2x160 <= (status[10:8] == 2);
	end
end

reg [3:0] clkdivpix;
always @(posedge clk64) clkdivpix <= clkdivpix + 1'b1;

wire ce_pix = (~clkdivpix[3] | ~hq2x160) & ~clkdivpix[2] & ~clkdivpix[1] & ~clkdivpix[0];
wire scandoubler = status[10:8] || forced_scandoubler;

assign CLK_VIDEO = clk64;
assign VIDEO_ARX = status[5:4] ? 8'd16 : 8'd4;
assign VIDEO_ARY = status[5:4] ? 8'd9  : 8'd3;
assign VGA_SL    = (status[10:8] > 2) ? status[9:8] - 2'd2 : 2'd0;
assign VGA_F1    = 0;

video_mixer video_mixer
(
	.clk_sys(clk64),
	.ce_pix(ce_pix),
	.ce_pix_out(CE_PIXEL),

	.scanlines(0),
	.hq2x(~status[10] & (status[9] ^ status[8])),
	.scandoubler(scandoubler),

	.R(r),
	.G(g),
	.B(b),
	.mono(0),

	.HSync(hsync_out),
	.VSync(vsync_out),
	.HBlank(hblank),
	.VBlank(vblank),

	.VGA_R(VGA_R),
	.VGA_G(VGA_G),
	.VGA_B(VGA_B),
	.VGA_VS(VGA_VS),
	.VGA_HS(VGA_HS),
	.VGA_DE(VGA_DE)
);

wire        opl_en = status[12];
wire [15:0] opl_out;
wire  [7:0] opl_dout;
opl3 opl_inst
(
	.clk(clk32),
	.clk_opl(clk64),
	.rst_n(reset_n),

	.period_80us(2560),

	.addr(c64_addr[4]),
	.dout(opl_dout),
	.we(~ram_we & IOF & opl_en & c64_addr[6] & ~c64_addr[5]),
	.din(c64_data_out),

	.sample_l(opl_out)
);

reg [31:0] ce_1m;
always @(posedge clk32) ce_1m <= reset_n ? {ce_1m[30:0], ce_1m[31]} : 1;

reg ioe_we;
always @(posedge clk32) begin
	reg old_ioe;

	old_ioe <= IOE;
	ioe_we <= ~old_ioe & IOE & ~ram_we;
end


wire [17:0] audio6581_r;
wire  [7:0] data_6581;
sid_top sid_6581
(
	.clock(clk32),
	.reset(~reset_n),
	.start_iter(ce_1m[31]),

	.addr(c64_addr[4:0]),
	.wren(status[17] ? ioe_we : sid_we),
	.wdata(c64_data_out),
	.rdata(data_6581),

	.extfilter_en(~status[6]),
	.sample_left(audio6581_r)
);

wire [17:0] audio8580_r;
wire  [7:0] data_8580;
sid8580 sid_8580
(
	.clk(clk32),
	.reset(~reset_n),
	.ce_1m(ce_1m[31]),

	.addr(c64_addr[4:0]),
	.we(status[17] ? ioe_we : sid_we),
	.data_in(c64_data_out),
	.data_out(data_8580),

	.extfilter_en(~status[6]),
	.audio_data(audio8580_r)
);	

wire [17:0] audio_r = status[16] ? audio8580_r : audio6581_r;

reg [15:0] al,ar;
always @(posedge clk32) begin
	reg [16:0] alm,arm;

	alm <= opl_en ? {opl_out[15],opl_out} + {audio_l[17],audio_l[17:2]} : {audio_l[17],audio_l[17:2]};
	arm <= opl_en ? {opl_out[15],opl_out} + {audio_r[17],audio_r[17:2]} : {audio_r[17],audio_r[17:2]};
	al <= ($signed(alm) > $signed(17'd32767)) ? 16'd32767 : ($signed(alm) < $signed(-17'd32768)) ? -16'd32768 : alm[15:0];
	ar <= ($signed(arm) > $signed(17'd32767)) ? 16'd32767 : ($signed(arm) < $signed(-17'd32768)) ? -16'd32768 : arm[15:0];
end

assign AUDIO_L = al;
assign AUDIO_R = ar;
assign AUDIO_S = 1;
assign AUDIO_MIX = status[19:18];

endmodule
