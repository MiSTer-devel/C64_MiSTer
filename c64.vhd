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
use IEEE.std_logic_unsigned.ALL;
use IEEE.numeric_std.all;

entity emu is port
(
	-- Master input clock
   CLK_50M          : in    std_logic;

   -- Async reset from top-level module.
   -- Can be used as initial reset.
   RESET            : in    std_logic;

	-- Must be passed to hps_io module
	HPS_BUS          : inout std_logic_vector(37 downto 0);

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
   AUDIO_S          : out   std_logic; -- 1 - signed audio samples, 0 - unsigned
   TAPE_IN          : in    std_logic;

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
		refclk   : in  std_logic := 'X'; -- clk
		rst      : in  std_logic := 'X'; -- reset
		outclk_0 : out std_logic;        -- clk
		outclk_1 : out std_logic;        -- clk
		locked   : out std_logic         -- export
	);
end component pll;


-- config string used by the io controller to fill the OSD
constant CONF_STR : string := 
	"C64;;" &
	"-;" &
	"F,PRG;" &
	"S,D64;" &
	"-;" &
	"O2,Video standard,PAL,NTSC;" &
	"O4,Aspect ratio,4:3,16:9;" &
	"O8A,Scandoubler Fx,None,HQ2x-320,HQ2x-160,CRT 25%,CRT 50%;" &
	"-;" &
	"O3,Joysticks,normal,swapped;" &
	"O6,Audio filter,On,Off;" &
	"-;" &
	"T5,Reset;" &
	"J,Fire;" &
	"V0,v0.27.33";

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


component hps_io generic(STRLEN : integer := 0); port
(
	CLK_SYS           : in  std_logic;
	HPS_BUS           : inout std_logic_vector(37 downto 0);

	conf_str          : in  std_logic_vector(8*STRLEN-1 downto 0);

	buttons           : out std_logic_vector(1 downto 0);
	forced_scandoubler : out std_logic;

	joystick_0        : out std_logic_vector(7 downto 0);
	joystick_1        : out std_logic_vector(7 downto 0);
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

	ps2_kbd_clk       : out std_logic;
	ps2_kbd_data      : out std_logic;

	ps2_mouse_clk     : out std_logic;
	ps2_mouse_data    : out std_logic;
	ps2_kbd_led_use   : in  std_logic_vector(2 downto 0);
	ps2_kbd_led_status: in  std_logic_vector(2 downto 0);

	ioctl_force_erase : in  std_logic;
	ioctl_erasing     : out std_logic;

	ioctl_download    : out std_logic;
	ioctl_index       : out std_logic_vector(7 downto 0);
	ioctl_wr          : out std_logic;
	ioctl_addr        : out std_logic_vector(24 downto 0);
	ioctl_dout        : out std_logic_vector(7 downto 0)
);
end component hps_io;


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


	signal c1541_reset : std_logic;
	signal buttons     : std_logic_vector(1 downto 0);
	
	-- signals to connect "data_io" for direct PRG injection
	signal ioctl_addr       : std_logic_vector(24 downto 0);
	signal ioctl_data       : std_logic_vector(7 downto 0);
	signal ioctl_index      : std_logic_vector(7 downto 0);
	signal ioctl_force_erase: std_logic;
	signal ioctl_erasing    : std_logic;
	signal ioctl_download   : std_logic;
	signal ioctl_wr         : std_logic;
	signal ioctl_we         : std_logic;

	signal c1541rom_wr    : std_logic;
	signal c64rom_wr      : std_logic;

	signal joyA           : std_logic_vector(7 downto 0);
	signal joyB           : std_logic_vector(7 downto 0);
	signal joyA_int       : std_logic_vector(5 downto 0);
	signal joyB_int       : std_logic_vector(5 downto 0);
	signal joyA_c64       : std_logic_vector(5 downto 0);
	signal joyB_c64       : std_logic_vector(5 downto 0);
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
	
	signal ps2_clk        : std_logic;
	signal ps2_dat        : std_logic;
	
	signal c64_iec_atn_i  : std_logic;
	signal c64_iec_clk_o  : std_logic;
	signal c64_iec_data_o : std_logic;
	signal c64_iec_atn_o  : std_logic;
	signal c64_iec_data_i : std_logic;
	signal c64_iec_clk_i  : std_logic;

	signal c1541_iec_atn_i  : std_logic;
	signal c1541_iec_clk_o  : std_logic;
	signal c1541_iec_data_o : std_logic;
	signal c1541_iec_atn_o  : std_logic;
	signal c1541_iec_data_i : std_logic;
	signal c1541_iec_clk_i  : std_logic;

	signal pll_locked: std_logic;
	signal clk32     : std_logic;
	signal clk64     : std_logic;
	signal clkdiv    : std_logic_vector(9 downto 0);
	signal ce_8      : std_logic;
	signal ce_4      : std_logic;
	signal hq2x160   : std_logic;

	signal sysram_ce        : std_logic;
	signal ram_ce           : std_logic;
	signal ram_ceD          : std_logic;
	signal ram_we           : std_logic;
	signal c64_addr         : unsigned(15 downto 0);
	signal c64_data_in_raw  : unsigned(7 downto 0);
	signal c64_data_in      : unsigned(7 downto 0);
	signal c64_data_out     : unsigned(7 downto 0);

	signal scandoubler : std_logic;
	signal forced_scandoubler : std_logic;
	signal ntsc_init_mode : std_logic;
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

	signal reset_counter : integer;
	signal reset_n       : std_logic;

begin


	LED_DISK  <= "00";
	LED_POWER <= "00";

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
		sd_ack_conf => open,
		sd_conf => '0',

		sd_buff_addr => sd_buff_addr,
		sd_buff_dout => sd_buff_dout,
		sd_buff_din => sd_buff_din,
		sd_buff_wr => sd_buff_wr,
		img_mounted => sd_change,
		img_readonly => disk_readonly,

		ps2_kbd_clk => ps2_clk,
		ps2_kbd_data => ps2_dat,
		ps2_kbd_led_use => "000",
		ps2_kbd_led_status => "000",

		ioctl_force_erase => ioctl_force_erase,
		ioctl_erasing => ioctl_erasing,

		ioctl_download => ioctl_download,
		ioctl_index => ioctl_index,
		ioctl_wr => ioctl_wr,
		ioctl_addr => ioctl_addr,
		ioctl_dout => ioctl_data
	);

	-- rearrange joystick contacta for c64
	joyA_int <= "0" & joyA(4) & joyA(0) & joyA(1) & joyA(2) & joyA(3);
	joyB_int <= "0" & joyB(4) & joyB(0) & joyB(1) & joyB(2) & joyB(3);

	-- swap joysticks if requested
	joyA_c64 <= joyB_int when status(3)='1' else joyA_int;
	joyB_c64 <= joyA_int when status(3)='1' else joyB_int;

	process(clk32)
	begin
		if rising_edge(clk32) then
			ram_ceD <= ram_ce;
	
			sysram_ce <= '0';
			if(ram_ceD = '1' and ram_ce = '0') then
				sysram_ce <= '1';
			end if;
			
			if(sysram_ce = '1') then
				if(ram_we = '0') then
					c64_data_in <= c64_data_out; -- short cut
				else
					c64_data_in <= c64_data_in_raw;
				end if;
			end if;

		end if;
	end process;

	ram: entity work.dpram
	port map
	(
		clk    => clk32,

		addr_a => unsigned(ioctl_addr(15 downto 0)),
		data_a => unsigned(ioctl_data),
		we_a   => ioctl_we,
		q_a    => open,

		addr_b => c64_addr,
		data_b => c64_data_out,
		we_b   => (not ram_we) and sysram_ce,
		q_b    => c64_data_in_raw
	);

	ioctl_we    <= ioctl_wr when (ioctl_index /= X"00") else '0';
	c64rom_wr   <= ioctl_wr when (ioctl_index = X"00") and (ioctl_addr(14) = '0') and (ioctl_download = '1') else '0';
	c1541rom_wr <= ioctl_wr when (ioctl_index = X"00") and (ioctl_addr(14) = '1') and (ioctl_download = '1') else '0';

	process(clk32)
	begin
		if rising_edge(clk32) then
			clkdiv <= std_logic_vector(unsigned(clkdiv)+1);
			if(clkdiv(1 downto 0) = "00") then
				ce_8 <= '1';
			else
				ce_8 <= '0';
			end if;
			if(clkdiv(2 downto 0) = "000") then
				ce_4 <= '1';
			else
				ce_4 <= '0';
			end if;
		end if;
	end process;

	ntsc_init_mode <= status(2);

   -- second  to generate 64mhz clock and phase shifted ram clock	
	mainpll : pll
	port map(
		refclk   => CLK_50M,
		rst      => '0',
		outclk_0 => clk32,
		outclk_1 => clk64,
		locked   => pll_locked
	);

	process(clk32)
	begin
		if rising_edge(clk32) then
			-- Reset by:
			-- Button at device, IO controller reboot, OSD or FPGA startup
			if status(0)='1' or pll_locked = '0' then
				reset_counter <= 1000000;
				reset_n <= '0';
			elsif buttons(1)='1' or status(5)='1' or reset_key = '1' then
				reset_counter <= 255;
				reset_n <= '0';
			elsif ioctl_download ='1' then
			elsif ioctl_erasing ='1' then
				ioctl_force_erase <= '0';
			else
				if reset_counter = 0 then
					reset_n <= '1';
				else
					reset_counter <= reset_counter - 1;
					if reset_counter = 100 then
						ioctl_force_erase <='1';
					end if;
				end if;
			end if;
		end if;
	end process;

	fpga64 : entity work.fpga64_sid_iec
	port map(
		clk32 => clk32,
		reset_n => reset_n,
		kbd_clk => not ps2_clk,
		kbd_dat => ps2_dat,
		ramAddr => c64_addr,
		ramDataOut => c64_data_out,
		ramDataIn => c64_data_in,
		ramCE => ram_ce,
		ramWe => ram_we,
		ntscInitMode => ntsc_init_mode,
		hsync => hsync,
		vsync => vsync,
		r => r,
		g => g,
		b => b,
		game => '1',
		exrom => '1',
		irq_n => '1',
		nmi_n => '1',
		dma_n => '1',
		ba => open,
		joyA => unsigned(joyA_c64),
		joyB => unsigned(joyB_c64),
		serioclk => open,
		ces => open,
		SIDclk => open,
		still => open,
		idle => open,
		audio_data => audio_data,
		extfilter_en => not status(6),
		iec_data_o => c64_iec_data_o,
		iec_atn_o  => c64_iec_atn_o,
		iec_clk_o  => c64_iec_clk_o,
		iec_data_i => not c64_iec_data_i,
		iec_clk_i  => not c64_iec_clk_i,
		iec_atn_i  => not c64_iec_atn_i,
		disk_num => open,
		c64rom_addr => ioctl_addr(13 downto 0),
		c64rom_data => ioctl_data,
		c64rom_wr => c64rom_wr,
		reset_key => reset_key
	);


   c64_iec_atn_i  <= not ((not c64_iec_atn_o)  and (not c1541_iec_atn_o) );
   c64_iec_data_i <= not ((not c64_iec_data_o) and (not c1541_iec_data_o));
	c64_iec_clk_i  <= not ((not c64_iec_clk_o)  and (not c1541_iec_clk_o) );

	c1541_iec_atn_i  <= c64_iec_atn_i;
	c1541_iec_data_i <= c64_iec_data_i;
	c1541_iec_clk_i  <= c64_iec_clk_i;

	process(clk32, reset_n)
		variable reset_cnt : integer range 0 to 100000;
	begin
		if reset_n = '0' then
			reset_cnt := 100000;
		elsif rising_edge(clk32) then
			if reset_cnt /= 0 then
				reset_cnt := reset_cnt - 1;
			end if;
		end if;

		if reset_cnt = 0 then
			c1541_reset <= '0';
		else 
			c1541_reset <= '1';
		end if;
	end process;

	c1541_sd : entity work.c1541_sd
	port map
	(
		clk32 => clk32,
		reset => c1541_reset,

		c1541rom_addr => ioctl_addr(13 downto 0),
		c1541rom_data => ioctl_data,
		c1541rom_wr => c1541rom_wr,

		disk_change => sd_change, 
		disk_readonly => disk_readonly,

		iec_atn_i  => c1541_iec_atn_i,
		iec_data_i => c1541_iec_data_i,
		iec_clk_i  => c1541_iec_clk_i,

		iec_atn_o  => c1541_iec_atn_o,
		iec_data_o => c1541_iec_data_o,
		iec_clk_o  => c1541_iec_clk_o,

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

	comp_sync : entity work.composite_sync
	port map
	(
		clk32 => clk32,
		hsync => hsync,
		vsync => vsync,
		ntsc  => ntsc_init_mode,
		hsync_out => hsync_out,
		vsync_out => vsync_out,
		hblank => hblank,
		vblank => vblank
	);

	ce_pix <= ce_4 when hq2x160='1' else ce_8;
	scandoubler <= '1' when (status(10 downto 8)/="000" or forced_scandoubler='1') else '0';

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

	VIDEO_ARX  <= "00000100" when (status(4) = '0') else "00010000";
	VIDEO_ARY  <= "00000011" when (status(4) = '0') else "00001001";

	AUDIO_L <= audio_data(17 downto 2);
	AUDIO_R <= audio_data(17 downto 2);
	AUDIO_S <= '1';

	CLK_VIDEO  <= clk64;

	SDRAM_CLK  <= '1';
	SDRAM_CKE  <= '0';
	SDRAM_A    <= (others => '0');
	SDRAM_BA   <= (others => '0');
	SDRAM_DQ   <= (others => 'Z');
	SDRAM_DQML <= '1';
	SDRAM_DQMH <= '1';
	SDRAM_nWE  <= '1';
	SDRAM_nCAS <= '1';
	SDRAM_nRAS <= '1';
	SDRAM_nCS  <= '1';

	DDRAM_CLK      <= '0';
	DDRAM_BURSTCNT <= (others => '0');
	DDRAM_ADDR     <= (others => '0');
	DDRAM_RD       <= '0';
	DDRAM_DIN      <= (others => '0');
	DDRAM_BE       <= (others => '0');
	DDRAM_WE       <= '0';

end struct;
