---------------------------------------------------------------------------------
-- DE2-35 Top level for FPGA64_027 by Dar (darfpga@aol.fr)
-- http://darfpga.blogspot.fr
--
-- FPGA64 is Copyrighted 2005-2008 by Peter Wendrich (pwsoft@syntiac.com)
-- http://www.syntiac.com/fpga64.html
--
-- Main features
--  15KHz(TV) / 31Khz(VGA) : board switch(0)
--  PAL(50Hz) / NTSC(60Hz) : board switch(1) and F12 key
--  PS2 keyboard input with portA / portB joystick emulation : F11 key
--  wm8731 sound output
--  64Ko of board SRAM used
--  External IEC bus available at gpio_1 (for drive 1541 or IEC/SD ...)
--   activated by switch(5) (activated with no hardware will stuck IEC bus)
--
--  Internal emulated 1541 on raw SD card : D64 images start at 25x6KB boundaries
--  Use hexidecimal disk editor such as HxD (www.mh-nexus.de) to build SD card.
--  Cut D64 file and paste at 0x00000 (first), 0x40000 (second), 0x80000 (third),
--  0xC0000(fourth), 0x100000(fith), 0x140000 (sixth) and so on.
--  BE CAREFUL NOT WRITING ON YOUR OWN HARDDRIVE
--
-- Uses only one pll for 32MHz and 18MHz generation from 50MHz
-- DE1 and DE0 nano Top level also available
--     
---------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use IEEE.std_logic_unsigned.ALL;

entity emu is port
(
	-- Master input clock
	CLK_50M          : in    std_logic;

	-- Async reset from top-level module.
	-- Can be used as initial reset.
	RESET            : in    std_logic;

	-- Must be passed to hps_io module
	HPS_BUS          : inout std_logic_vector(44 downto 0);

	-- Base video clock. Usually equals to CLK_SYS.
	CLK_VIDEO        : out   std_logic;

	-- Multiple resolutions are supported using different CE_PIXEL rates.
	-- Must be based on CLK_VIDEO
	CE_PIXEL         : out   std_logic;

	-- Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
	VIDEO_ARX        : out   std_logic_vector(7 downto 0);
	VIDEO_ARY        : out   std_logic_vector(7 downto 0);

	-- VGA
	VGA_R            : out   std_logic_vector(7 downto 0);
	VGA_G            : out   std_logic_vector(7 downto 0);
	VGA_B            : out   std_logic_vector(7 downto 0);
	VGA_HS           : out   std_logic; -- positive pulse!
	VGA_VS           : out   std_logic; -- positive pulse!
	VGA_DE           : out   std_logic; -- = not (VBlank or HBlank)

	-- LED
	LED_USER         : out   std_logic; -- 1 - ON, 0 - OFF.

	-- b[1]: 0 - LED status is system status ORed with b[0]
	--       1 - LED status is controled solely by b[0]
	-- hint: supply 2'b00 to let the system control the LED.
	LED_POWER        : out   std_logic_vector(1 downto 0);
	LED_DISK         : out   std_logic_vector(1 downto 0);

	-- AUDIO
	AUDIO_L          : out   std_logic_vector(15 downto 0);
	AUDIO_R          : out   std_logic_vector(15 downto 0);
	AUDIO_S          : out   std_logic;                    -- 1 - signed audio samples, 0 - unsigned
	AUDIO_MIX        : out   std_logic_vector(1 downto 0); -- 0 - no mix, 1 - 25%, 2 - 50%, 3 - 100% (mono)
	TAPE_IN          : in    std_logic;

	-- SD-SPI
	SD_SCK           : out   std_logic := 'Z';
	SD_MOSI          : out   std_logic := 'Z';
	SD_MISO          : in    std_logic;
	SD_CS            : out   std_logic := 'Z';
	SD_CD            : in    std_logic;

	-- High latency DDR3 RAM interface
	-- Use for non-critical time purposes
	DDRAM_CLK        : out   std_logic;
	DDRAM_BUSY       : in    std_logic;
	DDRAM_BURSTCNT   : out   std_logic_vector(7 downto 0);
	DDRAM_ADDR       : out   std_logic_vector(28 downto 0);
	DDRAM_DOUT       : in    std_logic_vector(63 downto 0);
	DDRAM_DOUT_READY : in    std_logic;
	DDRAM_RD         : out   std_logic;
	DDRAM_DIN        : out   std_logic_vector(63 downto 0);
	DDRAM_BE         : out   std_logic_vector(7 downto 0);
	DDRAM_WE         : out   std_logic;

	-- SDRAM interface with lower latency
	SDRAM_CLK        : out   std_logic;
	SDRAM_CKE        : out   std_logic;
	SDRAM_A          : out   std_logic_vector(12 downto 0);
	SDRAM_BA         : out   std_logic_vector(1 downto 0);
	SDRAM_DQ         : inout std_logic_vector(15 downto 0);
	SDRAM_DQML       : out   std_logic;
	SDRAM_DQMH       : out   std_logic;
	SDRAM_nCS        : out   std_logic;
	SDRAM_nCAS       : out   std_logic;
	SDRAM_nRAS       : out   std_logic;
	SDRAM_nWE        : out   std_logic
);
end emu;

architecture struct of emu is

component pll is
	port (
		refclk   : in  std_logic; -- clk
		rst      : in  std_logic; -- reset
		outclk_0 : out std_logic; -- clk
		outclk_1 : out std_logic; -- clk
		outclk_2 : out std_logic; -- clk
		locked   : out std_logic  -- export
	);
end component pll;


-- config string used by the io controller to fill the OSD
constant CONF_STR : string := 
	"C64;;" &
	"-;" &
	"S,D64,Mount Disk;" &
	"-;" &
	"F,PRG,Load File;" &
	"F,CRT,Load Cartridge;" &
	"-;" &
	"O2,Video standard,PAL,NTSC;" &
	"O45,Aspect ratio,Original,Wide,Zoom;" &
	"O8A,Scandoubler Fx,None,HQ2x-320,HQ2x-160,CRT 25%,CRT 50%;" &
	"-;" &
	"OD,SID,6581,8580;" &
	"O6,Audio filter,On,Off;" &
	"OC,Sound expander,No,OPL2;" &
	"-;" &
	"O3,Primary joystick,Port 2,Port 1;" &
	"OB,BIOS,C64,C64GS;" &
	"R0,Reset & Detach cartridge;" &
	"J,Button 1,Button 2,Button 3;" &
	"V0,v0.27.58";

---------
-- ARM IO
---------


-- convert string to std_logic_vector to be given to user_io
function to_slv(s: string) return std_logic_vector is 
  constant ss: string(1 to s'length) := s; 
  variable rval: std_logic_vector(1 to 8 * s'length); 
  variable p: integer; 
  variable c: integer; 
begin
  for i in ss'range loop
    p := 8 * i;
    c := character'pos(ss(i));
    rval(p - 7 to p) := std_logic_vector(to_unsigned(c,8)); 
  end loop; 
  return rval; 
end function; 

component hps_io generic
(
	STRLEN : integer := 0;
	PS2DIV : integer := 1000;
	WIDE   : integer := 0;
	VDNUM  : integer := 1;
	PS2WE  : integer := 0
);
port
(
	CLK_SYS           : in  std_logic;
	HPS_BUS           : inout std_logic_vector(44 downto 0);

	conf_str          : in  std_logic_vector(8*STRLEN-1 downto 0);

	buttons           : out std_logic_vector(1 downto 0);
	forced_scandoubler: out std_logic;

	joystick_0        : out std_logic_vector(15 downto 0);
	joystick_1        : out std_logic_vector(15 downto 0);
	joystick_analog_0 : out std_logic_vector(15 downto 0);
	joystick_analog_1 : out std_logic_vector(15 downto 0);
	status            : out std_logic_vector(31 downto 0);

	sd_lba            : in  std_logic_vector(31 downto 0);
	sd_rd             : in  std_logic;
	sd_wr             : in  std_logic;
	sd_ack            : out std_logic;
	sd_conf           : in  std_logic;
	sd_ack_conf       : out std_logic;

	sd_buff_addr      : out std_logic_vector(8 downto 0);
	sd_buff_dout      : out std_logic_vector(7 downto 0);
	sd_buff_din       : in  std_logic_vector(7 downto 0);
	sd_buff_wr        : out std_logic;

	img_mounted       : out std_logic;
	img_size          : out std_logic_vector(63 downto 0);
	img_readonly      : out std_logic;

	ioctl_download    : out std_logic;
	ioctl_index       : out std_logic_vector(7 downto 0);
	ioctl_wr          : out std_logic;
	ioctl_addr        : out std_logic_vector(24 downto 0);
	ioctl_dout        : out std_logic_vector(7 downto 0);
	ioctl_wait        : in  std_logic;
	
	RTC               : out std_logic_vector(64 downto 0);
	TIMESTAMP         : out std_logic_vector(32 downto 0);

	ps2_kbd_clk_out   : out std_logic;
	ps2_kbd_data_out  : out std_logic;
	ps2_kbd_clk_in    : in  std_logic;
	ps2_kbd_data_in   : in  std_logic;

	ps2_kbd_led_use   : in  std_logic_vector(2 downto 0);
	ps2_kbd_led_status: in  std_logic_vector(2 downto 0);

	ps2_mouse_clk_out : out std_logic;
	ps2_mouse_data_out: out std_logic;
	ps2_mouse_clk_in  : in  std_logic;
	ps2_mouse_data_in : in  std_logic;

	ps2_key           : out std_logic_vector(10 downto 0);
	ps2_mouse         : out std_logic_vector(24 downto 0)
);
end component hps_io;

component sdram is port
(
   -- interface to the MT48LC16M16 chip
   sd_addr    : out   std_logic_vector(12 downto 0);
   sd_cs      : out   std_logic;
   sd_ba      : out   std_logic_vector(1 downto 0);
   sd_we      : out   std_logic;
   sd_ras     : out   std_logic;
   sd_cas     : out   std_logic;

   -- system interface
   clk        : in    std_logic;
   init       : in    std_logic;

   -- cpu/chipset interface
   addr       : in    std_logic_vector(24 downto 0);
   refresh    : in    std_logic;
   we         : in    std_logic;
   ce         : in    std_logic
);
end component;

component video_mixer generic ( LINE_LENGTH : integer := 512; HALF_DEPTH : integer := 0 ); port
(
	clk_sys   : in  std_logic;
	ce_pix    : in  std_logic;
	ce_pix_out: out std_logic;

	scandoubler : in std_logic;
	scanlines : in  std_logic_vector(1 downto 0);
	hq2x      : in  std_logic;

	R, G, B   : in  std_logic_vector(7 downto 0);
	mono      : in  std_logic;

	HSync, VSync   : in std_logic;
	HBlank, VBlank : in std_logic;

	VGA_R,VGA_G, VGA_B : out std_logic_vector(7 downto 0);
	VGA_VS, VGA_HS     : out std_logic;
	VGA_DE             : out std_logic
);
end component video_mixer;

--------------------------
-- cartridge - LCA mar17 -
--------------------------
component cartridge port
(
	romL			: in  std_logic;									-- romL signal in
	romH			: in  std_logic;									-- romH signal in
	UMAXromH		: in  std_logic;									-- VIC II ultimax read access flag
	mem_write	: in  std_logic;									-- memory write active
	mem_ce		: in  std_logic;
	mem_ce_out  : out std_logic;
	IOE			: in  std_logic;									-- IOE signal &DE00
	IOF			: in  std_logic;									-- IOF signal &DF00

	clk32			: in  std_logic;									-- 32mhz clock source
	reset			: in  std_logic;									-- reset signal
	reset_out	: out std_logic;									-- reset signal

	cart_id		: in  std_logic_vector(15 downto 0);		-- cart ID or cart type
	cart_exrom  : in  std_logic_vector(7 downto 0);			-- CRT file EXROM status
	cart_game   : in  std_logic_vector(7 downto 0);			-- CRT file GAME status

	cart_bank_laddr : in std_logic_vector(15 downto 0);	-- 1st bank loading address
	cart_bank_size  : in std_logic_vector(15 downto 0);	-- length of each bank
	cart_bank_num   : in std_logic_vector(15 downto 0);
	cart_bank_type  : in std_logic_vector(7 downto 0);
	cart_bank_raddr : in std_logic_vector(24 downto 0);	-- chip packet address
	cart_bank_wr    : in std_logic;

	cart_attached: in std_logic;									-- FLAG to say cart has been loaded
	cart_loading : in std_logic;

	c64_mem_address_in: in std_logic_vector(15 downto 0);	-- address from cpu
	c64_data_out: in std_logic_vector(7 downto 0);			-- data from cpu going to sdram

	sdram_address_out: out std_logic_vector(24 downto 0); -- translated address output
	exrom       : out std_logic;									-- exrom line
	game        : out std_logic;									-- game line
	IOE_ena     : out std_logic;
	IOF_ena     : out std_logic;
	max_ram     : out std_logic;
	freeze_key  : in  std_logic;
	nmi         : out std_logic;
	nmi_ack     : in  std_logic
);

end component cartridge;

component opl3 port
(
    clk          : in  std_logic;
    clk_opl      : in  std_logic;
    rst_n        : in  std_logic;
    irq_n        : out std_logic;

	 period_80us  : in  std_logic_vector(12 downto 0);

    addr         : in  std_logic_vector(1 downto 0);
    dout         : out std_logic_vector(7 downto 0);
    we           : in  std_logic;
    din          : in  std_logic_vector(7 downto 0);

    sample_l     : out signed(15 downto 0);
    sample_r     : out signed(15 downto 0)
);
end component;


	signal idle             : std_logic;
	signal ces              : std_logic_vector(3 downto 0);
	signal iec_cycle        : std_logic;
	signal iec_cycleD       : std_logic;
	signal buttons          : std_logic_vector(1 downto 0);

	-- signals to connect "data_io" for direct PRG injection
	signal ioctl_wr         : std_logic;
	signal ioctl_addr       : std_logic_vector(24 downto 0);
	signal ioctl_data       : std_logic_vector(7 downto 0);
	signal ioctl_index      : std_logic_vector(7 downto 0);
	signal ioctl_ram_addr   : std_logic_vector(24 downto 0);
	signal ioctl_ram_data   : std_logic_vector(7 downto 0);
	signal ioctl_load_addr  : std_logic_vector(24 downto 0);						--load address from mist.io LCA
	signal ioctl_req_wr     : std_logic := '0';
	signal ioctl_iec_cycle_used: std_logic;
	signal ioctl_download   : std_logic;
	signal c64_addr         : std_logic_vector(15 downto 0);
	signal c64_data_in      : std_logic_vector(7 downto 0);
	signal c64_data_out     : std_logic_vector(7 downto 0);
	signal sdram_addr       : std_logic_vector(24 downto 0);
	signal sdram_data_out   : std_logic_vector(7 downto 0);
	signal sdram_we         : std_logic;
	signal sdram_ce         : std_logic;

	signal old_download     : std_logic;
	signal force_erase      : std_logic;
	signal erasing          : std_logic;
	signal erase_to         : std_logic_vector(4 downto 0) := (others => '0');
	signal erase_cram       : std_logic := '0';

	signal cart_id 			: std_logic_vector(15 downto 0);					-- cart ID or cart type
	signal cart_bank_laddr 	: std_logic_vector(15 downto 0) := (others => '0'); -- 1st bank loading address
	signal cart_bank_size 	: std_logic_vector(15 downto 0) := (others => '0'); -- length of each bank
	signal cart_bank_num 	: std_logic_vector(15 downto 0) := (others => '0'); -- bank number
	signal cart_bank_type 	: std_logic_vector(7 downto 0) := (others => '0');	 -- bank type
	signal cart_exrom			: std_logic_vector(7 downto 0);					-- CRT file EXROM status
	signal cart_game			: std_logic_vector(7 downto 0);					-- CRT file GAME status
	signal cart_attached		: std_logic;
	signal game					: std_logic;											-- game line to cpu
	signal exrom				: std_logic;											-- exrom line to cpu
	signal IOE_rom 			: std_logic;
	signal IOF_rom 			: std_logic;
	signal max_ram 			: std_logic;

	signal defxx				: std_logic;
	signal IOE					: std_logic;											-- IOE signal
	signal IOF					: std_logic;											-- IOF signal
	signal cartridge_reset	: std_logic;											-- FLAG to reset once cart loaded
	signal c64_addr_temp    : std_logic_vector(24 downto 0);	
	signal mem_ce           : std_logic;
	signal reset_crt        : std_logic;
	signal freeze_key       : std_logic;
	signal nmi              : std_logic;
	signal nmi_ack          : std_logic;

	signal cart_loading	   : std_logic;
	signal cart_hdr_cnt     : std_logic_vector(3 downto 0);
	signal cart_hdr_wr	   : std_logic;
	signal cart_blk_len     : std_logic_vector(31 downto 0);

	signal romL				   : std_logic;												-- cart romL from buslogic LCA
	signal romH				   : std_logic;												-- cart romH from buslogic LCA
	signal UMAXromH		   : std_logic;												-- VIC II Ultimax access - LCA

	signal c1541rom_wr    : std_logic;
	signal c64rom_wr      : std_logic;

	signal joyA           : std_logic_vector(15 downto 0);
	signal joyB           : std_logic_vector(15 downto 0);
	signal joyA_int       : std_logic_vector(6 downto 0);
	signal joyB_int       : std_logic_vector(6 downto 0);
	signal joyA_c64       : std_logic_vector(6 downto 0);
	signal joyB_c64       : std_logic_vector(6 downto 0);
	signal reset_key      : std_logic;
	
	signal status         : std_logic_vector(31 downto 0);

	signal sd_lba         : std_logic_vector(31 downto 0);
	signal sd_rd          : std_logic;
	signal sd_wr          : std_logic;
	signal sd_ack         : std_logic;
	signal sd_buff_addr   : std_logic_vector(8 downto 0);
	signal sd_buff_dout   : std_logic_vector(7 downto 0);
	signal sd_buff_din    : std_logic_vector(7 downto 0);
	signal sd_buff_wr     : std_logic;
	signal sd_change      : std_logic;
	signal disk_readonly  : std_logic;
	
	signal ps2_key        : std_logic_vector(10 downto 0);
	
	signal c64_iec_clk_o  : std_logic;
	signal c64_iec_data_o : std_logic;
	signal c64_iec_atn_o  : std_logic;
	signal c1541_iec_clk_o  : std_logic;
	signal c1541_iec_data_o : std_logic;

	alias  c64_addr_int : unsigned is unsigned(c64_addr);
	alias  c64_data_in_int   : unsigned is unsigned(c64_data_in);
	signal c64_data_in16: std_logic_vector(15 downto 0);
	alias  c64_data_out_int   : unsigned is unsigned(c64_data_out);
	signal pll_locked: std_logic;
	signal clk32     : std_logic;
	signal clk64     : std_logic;
	signal hq2x160   : std_logic;

	signal sysram_ce        : std_logic;
	signal ram_ce           : std_logic;
	signal ram_ceD          : std_logic;
	signal ram_we           : std_logic;

	signal scandoubler : std_logic;
	signal forced_scandoubler : std_logic;
	signal clkdivpix : std_logic_vector(3 downto 0);
	signal ce_pix    : std_logic;
	signal r,g,b     : unsigned(7 downto 0);
	signal hsync     : std_logic;
	signal vsync     : std_logic;
	signal hblank    : std_logic;
	signal vblank    : std_logic;
	signal old_vsync : std_logic;
	signal hsync_out : std_logic;
	signal vsync_out : std_logic;
	signal scanlines : std_logic_vector(1 downto 0);

	signal audio_data : std_logic_vector(17 downto 0);
	signal sid_out    : signed(15 downto 0);
	signal opl_out    : signed(15 downto 0);
	signal audio_out  : signed(15 downto 0);

	signal opl_dout   : std_logic_vector(7 downto 0);
	signal opl_en     : std_logic;

	signal reset_counter : integer;
	signal reset_n       : std_logic;

begin


	LED_DISK  <= "00";
	LED_POWER <= "00";
	iec_cycle <= '1' when ces = "1011" else '0';

	-- User io
	hps : hps_io
	generic map (STRLEN => CONF_STR'length)
	port map (
		clk_sys => clk32,
		HPS_BUS => HPS_BUS,

		joystick_0 => joyA,
		joystick_1 => joyB,

		conf_str => to_slv(CONF_STR),

		status => status,
		buttons => buttons,
		forced_scandoubler => forced_scandoubler,

		sd_lba => sd_lba,
		sd_rd => sd_rd,
		sd_wr => sd_wr,
		sd_ack => sd_ack,
		sd_conf => '0',

		sd_buff_addr => sd_buff_addr,
		sd_buff_dout => sd_buff_dout,
		sd_buff_din => sd_buff_din,
		sd_buff_wr => sd_buff_wr,
		img_mounted => sd_change,
		img_readonly => disk_readonly,

		ps2_key => ps2_key,
		ps2_kbd_led_use => "000",
		ps2_kbd_led_status => "000",

		ps2_kbd_clk_in => '1',
		ps2_kbd_data_in => '1',
		ps2_mouse_clk_in => '1',
		ps2_mouse_data_in => '1',

		ioctl_download => ioctl_download,
		ioctl_index => ioctl_index,
		ioctl_wr => ioctl_wr,
		ioctl_addr => ioctl_addr,
		ioctl_dout => ioctl_data,
		ioctl_wait => ioctl_req_wr
	);

	cart_loading <= '1' when ioctl_download = '1' and ioctl_index = 3 else '0';

	cart : cartridge
	port map (
		romL => romL,		
		romH => romH,	
		UMAXromH => UMAXromH,
		IOE => IOE,
		IOF => IOF,
		mem_write => not ram_we,	
		mem_ce => not ram_ce,
		mem_ce_out => mem_ce,

	 	clk32 => clk32,			
		reset => reset_n,
		reset_out => reset_crt,
		
		cart_id => cart_id,		
		cart_exrom => cart_exrom,
		cart_game => cart_game,

		cart_bank_laddr => cart_bank_laddr,
		cart_bank_size => cart_bank_size,
		cart_bank_num => cart_bank_num,
		cart_bank_type => cart_bank_type,
		cart_bank_raddr => ioctl_load_addr,
		cart_bank_wr => cart_hdr_wr,
		
	 	cart_attached => cart_attached,
		cart_loading => cart_loading,
		
		c64_mem_address_in => c64_addr,
		c64_data_out => c64_data_out,
		
		sdram_address_out => c64_addr_temp,
		exrom	=> exrom,							
		game => game,
		IOE_ena => ioE_rom,
		IOF_ena => ioF_rom,
		max_ram => max_ram,
		freeze_key => freeze_key,
		nmi => nmi,
		nmi_ack => nmi_ack
	);

	-- rearrange joystick contacts for c64
	joyA_int <= joyA(6 downto 4) & joyA(0) & joyA(1) & joyA(2) & joyA(3);
	joyB_int <= joyB(6 downto 4) & joyB(0) & joyB(1) & joyB(2) & joyB(3);

	-- swap joysticks if requested
	joyA_c64 <= joyB_int when status(3)='1' else joyA_int;
	joyB_c64 <= joyA_int when status(3)='1' else joyB_int;

	-- multiplex ram port between c64 core and data_io (io controller dma)
	sdram_addr <= c64_addr_temp when iec_cycle='0' else ioctl_ram_addr; -- old line lca
	sdram_data_out <= c64_data_out when iec_cycle='0' else ioctl_ram_data;
	-- ram_we and ce are active low
	sdram_ce <=     mem_ce when iec_cycle='0' else ioctl_iec_cycle_used;
	sdram_we <= not ram_we when iec_cycle='0' else ioctl_iec_cycle_used;

	process(clk32)
	begin
		if falling_edge(clk32) then

			old_download <= ioctl_download;
			iec_cycleD <= iec_cycle;
			cart_hdr_wr <= '0';

			if(iec_cycle='1' and iec_cycleD='0' and ioctl_req_wr='1') then
				ioctl_req_wr <= '0';
				ioctl_iec_cycle_used <= '1';
				ioctl_ram_addr  <= ioctl_load_addr;
				ioctl_load_addr <= ioctl_load_addr + "1";
				if erasing = '1' then
					ioctl_ram_data  <= (others => '0');
				else
					ioctl_ram_data <= ioctl_data;
				end if;
			else 
				if(iec_cycle='0') then
					ioctl_iec_cycle_used <= '0';
				end if;
			end if;

			if ioctl_wr='1' then
				if ioctl_index = 2 then
					if ioctl_addr = 0 then
						ioctl_load_addr(7 downto 0) <= ioctl_data;
					elsif(ioctl_addr = 1) then
						ioctl_load_addr(15 downto 8) <= ioctl_data;
					else
						ioctl_req_wr <= '1';
					end if;
				end if;

				if ioctl_index = 3 then
					if ioctl_addr = 0 then
						ioctl_load_addr <= '0' & X"100000";
						cart_blk_len <= (others => '0');
						cart_hdr_cnt <= (others => '0');
					end if;

					if(ioctl_addr = X"16") then cart_id(15 downto 8)  <= ioctl_data; end if;
					if(ioctl_addr = X"17") then cart_id(7 downto 0)   <= ioctl_data; end if;
					if(ioctl_addr = X"18") then cart_exrom(7 downto 0)<= ioctl_data; end if;
					if(ioctl_addr = X"19") then cart_game(7 downto 0) <= ioctl_data; end if;

					if(ioctl_addr >= X"40") then
						if cart_blk_len = 0 and cart_hdr_cnt = 0 then
							cart_hdr_cnt <= X"1";
							if ioctl_load_addr(12 downto 0) /= 0 then
							   -- align to 8KB boundary
								ioctl_load_addr(12 downto 0) <= '0' & X"000";
								ioctl_load_addr(24 downto 13) <= ioctl_load_addr(24 downto 13) + "1";
							end if;
						elsif cart_hdr_cnt /= 0 then
							cart_hdr_cnt <= cart_hdr_cnt + "1";
							if(cart_hdr_cnt = 4)  then cart_blk_len(31 downto 24)  <= ioctl_data; end if;
							if(cart_hdr_cnt = 5)  then cart_blk_len(23 downto 16)  <= ioctl_data; end if;
							if(cart_hdr_cnt = 6)  then cart_blk_len(15 downto 8)   <= ioctl_data; end if;
							if(cart_hdr_cnt = 7)  then cart_blk_len(7 downto 0)    <= ioctl_data; end if;
							if(cart_hdr_cnt = 8)  then cart_blk_len <= cart_blk_len - X"10";		 end if;
							if(cart_hdr_cnt = 9)  then cart_bank_type              <= ioctl_data; end if;
							if(cart_hdr_cnt = 10) then cart_bank_num(15 downto 8)  <= ioctl_data; end if;
							if(cart_hdr_cnt = 11) then cart_bank_num(7 downto 0)   <= ioctl_data; end if;
							if(cart_hdr_cnt = 12) then cart_bank_laddr(15 downto 8)<= ioctl_data; end if;
							if(cart_hdr_cnt = 13) then cart_bank_laddr(7 downto 0) <= ioctl_data; end if;
							if(cart_hdr_cnt = 14) then cart_bank_size(15 downto 8) <= ioctl_data; end if;
							if(cart_hdr_cnt = 15) then cart_bank_size(7 downto 0)  <= ioctl_data; end if;
							if(cart_hdr_cnt = 15) then cart_hdr_wr <= '1';                        end if;
						else
							cart_blk_len <= cart_blk_len - "1";
							ioctl_req_wr <= '1';
						end if;
					end if;
				end if;
			end if;
			
			if old_download /= ioctl_download and ioctl_index = 3 then
				cart_attached <= old_download;
				erase_cram <= '1';
			end if;

			if status(0)='1' or buttons(1)='1' then
				cart_attached <= '0';
			end if;
			
			if erasing='0' and force_erase = '1' then
				erasing <='1';
				ioctl_load_addr <= (others => '0');
			end if;

			if erasing = '1' and ioctl_req_wr = '0' then
				erase_to <= erase_to + "1";
				if erase_to = "11111" then
					if ioctl_load_addr < (erase_cram & X"FFFF") then 
						ioctl_req_wr <= '1';
					else
						erasing <= '0';
						erase_cram <= '0';
					end if;
				end if;
			end if;
		end if;
	end process;

	c64rom_wr   <= ioctl_wr when (ioctl_index = 0) and (ioctl_addr(14) = '0') and (ioctl_download = '1') else '0';
	c1541rom_wr <= ioctl_wr when (ioctl_index = 0) and (ioctl_addr(14) = '1') and (ioctl_download = '1') else '0';

	mainpll : pll
	port map(
		refclk   => CLK_50M,
		rst      => '0',
		outclk_0 => clk64,
		outclk_1 => SDRAM_CLK,
		outclk_2 => clk32,
		locked   => pll_locked
	);

	process(clk32)
	begin
		if rising_edge(clk32) then
			-- Reset by:
			-- Button at device, IO controller reboot, OSD or FPGA startup
			if status(0)='1' or buttons(1)='1' or pll_locked = '0' then
				reset_counter <= 100000;
				reset_n <= '0';
			elsif reset_key = '1' or reset_crt='1' or (ioctl_download='1' and ioctl_index = 3) then
				reset_counter <= 255;
				reset_n <= '0';
			elsif ioctl_download ='1' then
			elsif erasing ='1' then
				force_erase <= '0';
			else
				if reset_counter = 0 then
					reset_n <= '1';
				else
					reset_counter <= reset_counter - 1;
					if reset_counter = 100 then
						force_erase <='1';
					end if;
				end if;
			end if;
		end if;
	end process;

	SDRAM_DQ(15 downto 8) <= (others => 'Z') when sdram_we='0' else (others => '0');
	SDRAM_DQ(7 downto 0) <= (others => 'Z') when sdram_we='0' else sdram_data_out;

	-- read from sdram
	c64_data_in <= SDRAM_DQ(7 downto 0);
	-- clock is always enabled and memory is never masked as we only
	-- use one byte
	SDRAM_CKE <= '1';
	SDRAM_DQML <= '0';
	SDRAM_DQMH <= '0';

	sdr: sdram port map(
		sd_addr => SDRAM_A,
		sd_ba => SDRAM_BA,
		sd_cs => SDRAM_nCS,
		sd_we => SDRAM_nWE,
		sd_ras => SDRAM_nRAS,
		sd_cas => SDRAM_nCAS,

		clk => clk64,
		addr => sdram_addr,
		init => not pll_locked,
		we => sdram_we,
		refresh => idle,       -- refresh ram in idle state
		ce => sdram_ce
	);

	fpga64 : entity work.fpga64_sid_iec
	port map(
		clk32 => clk32,
		reset_n => reset_n,
		c64gs => status(11),
		ps2_key => ps2_key,
		ramAddr => c64_addr_int,
		ramDataOut => c64_data_out_int,
		ramDataIn => c64_data_in_int,
		ramCE => ram_ce,
		ramWe => ram_we,
		ntscMode => status(2),
		hsync => hsync,
		vsync => vsync,
		r => r,
		g => g,
		b => b,
		game => game,
		exrom => exrom,
		ioE_rom => ioE_rom,
		ioF_rom => ioF_rom,
		max_ram => max_ram,
		UMAXromH => UMAXromH,
		CPU_hasbus => open,
		irq_n => '1',
		nmi_n => not nmi,
		nmi_ack => nmi_ack,
		freeze_key => freeze_key,
		dma_n => '1',
		romL => romL,			-- cart signals LCA
		romH => romH,			-- cart signals LCA
		IOE => IOE,				-- cart signals LCA										
		IOF => IOF,				-- cart signals LCA
		ioF_ext => opl_en,
		ioE_ext => '0',
		io_data => unsigned(opl_dout),
		ba => open,
		joyA => unsigned(joyA_c64),
		joyB => unsigned(joyB_c64),
		serioclk => open,
		ces => ces,
		SIDclk => open,
		still => open,
		idle => idle,
		audio_data => audio_data,
		extfilter_en => not status(6),
		sid_ver => status(13),
		iec_data_o => c64_iec_data_o,
		iec_atn_o  => c64_iec_atn_o,
		iec_clk_o  => c64_iec_clk_o,
		iec_data_i => c1541_iec_data_o,
		iec_clk_i  => c1541_iec_clk_o,
		c64rom_addr => ioctl_addr(13 downto 0),
		c64rom_data => ioctl_data,
		c64rom_wr => c64rom_wr,
		reset_key => reset_key
	);

	c1541_sd : entity work.c1541_sd
	port map
	(
		clk32 => clk32,

		c1541rom_clk => clk32,
		c1541rom_addr => ioctl_addr(13 downto 0),
		c1541rom_data => ioctl_data,
		c1541rom_wr => c1541rom_wr,

		disk_change => sd_change, 
		disk_readonly => disk_readonly,

		iec_atn_i  => c64_iec_atn_o,
		iec_data_i => c64_iec_data_o,
		iec_clk_i  => c64_iec_clk_o,
		iec_data_o => c1541_iec_data_o,
		iec_clk_o  => c1541_iec_clk_o,
		iec_reset_i=> not reset_n,

		sd_lba => sd_lba,
		sd_rd  => sd_rd,
		sd_wr  => sd_wr,
		sd_ack => sd_ack,
		sd_buff_addr => sd_buff_addr,
		sd_buff_dout => sd_buff_dout,
		sd_buff_din  => sd_buff_din,
		sd_buff_wr   => sd_buff_wr,

		led => LED_USER
	);

	sync : entity work.video_sync
	port map
	(
		clk32 => clk32,
		hsync => hsync,
		vsync => vsync,
		ntsc  => status(2),
		wide  => status(5),
		hsync_out => hsync_out,
		vsync_out => vsync_out,
		hblank => hblank,
		vblank => vblank
	);

	process(clk32)
	begin
		if rising_edge(clk32) then
			if((old_vsync = '0') and (vsync_out = '1')) then
				if(status(10 downto 8)="010") then
					hq2x160 <= '1';
				else
					hq2x160 <= '0';
				end if;
			end if;
			old_vsync <= vsync_out;
		end if;
	end process;

	clkdivpix <= clkdivpix+"1" when rising_edge(clk64);
	ce_pix <= (not clkdivpix(3) or not hq2x160) and not clkdivpix(2) and not clkdivpix(1) and not clkdivpix(0);

	scandoubler <= '1' when (status(10 downto 8)/="000" or forced_scandoubler='1') else '0';
	scanlines <= "01" when status(10 downto 8) = "011" else "10" when status(10 downto 8) = "100" else "00";

	vmixer : video_mixer
	port map
	(
		clk_sys => clk64,
		ce_pix  => ce_pix,
		ce_pix_out => CE_PIXEL,

		scanlines => scanlines,
		hq2x => status(9) xor status(8),
		scandoubler => scandoubler,

		R => std_logic_vector(r),
		G => std_logic_vector(g),
		B => std_logic_vector(b),
		mono => '0',

		HSync  => hsync_out,
		VSync  => vsync_out,
		HBlank => hblank,
		VBlank => vblank,

		VGA_R  => VGA_R,
		VGA_G  => VGA_G,
		VGA_B  => VGA_B,
		VGA_VS => VGA_VS,
		VGA_HS => VGA_HS,
		VGA_DE => VGA_DE
	);
	
	opl_en <= status(12);

	opl_inst : opl3
	port map
	(
		 clk => clk32,
		 clk_opl => clk64,
		 rst_n => reset_n,
		 
		 period_80us => std_logic_vector(to_unsigned(2560, 13)),

		 addr => '0' & c64_addr(4),
		 dout => opl_dout,
		 we => (not ram_we) and IOF and opl_en and c64_addr(6) and (not c64_addr(5)),
		 din => c64_data_out,

		 sample_l => opl_out
	);

	sid_out <= signed(audio_data(17 downto 2));
	audio_out <= sid_out when opl_en = '0' else shift_right(opl_out,1) + shift_right(sid_out,1);

	AUDIO_L    <= std_logic_vector(audio_out);
	AUDIO_R    <= std_logic_vector(audio_out);
	AUDIO_S    <= '1';
	AUDIO_MIX  <= "00";

	VIDEO_ARX  <= X"04" when (status(5 downto 4) = "00") else X"10";
	VIDEO_ARY  <= X"03" when (status(5 downto 4) = "00") else X"09";

	CLK_VIDEO  <= clk64;

	DDRAM_CLK  <= '0';
	DDRAM_BURSTCNT <= (others => '0');
	DDRAM_ADDR <= (others => '0');
	DDRAM_RD   <= '0';
	DDRAM_DIN  <= (others => '0');
	DDRAM_BE   <= (others => '0');
	DDRAM_WE   <= '0';

	SD_SCK     <= 'Z';
	SD_MOSI    <= 'Z';
	SD_CS      <= 'Z';
end struct;
