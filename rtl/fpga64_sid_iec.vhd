-- -----------------------------------------------------------------------
--
--                                 FPGA 64
--
--     A fully functional commodore 64 implementation in a single FPGA
--
-- -----------------------------------------------------------------------
-- Peter Wendrich (pwsoft@syntiac.com)
-- http://www.syntiac.com/fpga64.html
-- -----------------------------------------------------------------------
--
-- System runs on 32 Mhz (derived from a 50MHz clock). 
-- The VIC-II runs in the first 4 cycles of 32 Mhz clock.
-- The CPU runs in the last 16 cycles. Effective cpu speed is 1 Mhz.
-- 4 additional cycles are used to interface with the C-One IEC port.
-- 
-- -----------------------------------------------------------------------
-- Dar 08/03/2014 
--
-- Based on fpga64_cone
-- add external selection for 15KHz(TV)/31KHz(VGA)
-- add external selection for power on NTSC(60Hz)/PAL(50Hz)
-- add external conection in/out for IEC signal
-- add sid entity 
-- -----------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.std_logic_unsigned.ALL;
use IEEE.numeric_std.all;

-- -----------------------------------------------------------------------

entity fpga64_sid_iec is
port(
	clk32       : in  std_logic;
	reset_n     : in  std_logic;
	bios        : in  std_logic_vector(1 downto 0);
	
	pause       : in  std_logic := '0';
	pause_out   : out std_logic;

	-- keyboard interface (use any ordinairy PS2 keyboard)
	ps2_key     : in  std_logic_vector(10 downto 0);
	kbd_reset   : in  std_logic := '0';

	-- external memory
	ramAddr     : out unsigned(15 downto 0);
	ramDin      : in  unsigned(7 downto 0);
	ramDout     : out unsigned(7 downto 0);

	ramCE       : out std_logic;
	ramWE       : out std_logic;

	io_cycle    : out std_logic;
	refresh     : out std_logic;

	cia_mode    : in  std_logic;
	turbo_mode  : in  std_logic_vector(1 downto 0);
	turbo_speed : in  std_logic_vector(1 downto 0);
	turbo_reset : in  std_logic;

	-- VGA/SCART interface
	ntscMode    : in  std_logic;
	hsync       : out std_logic;
	vsync       : out std_logic;
	r           : out unsigned(7 downto 0);
	g           : out unsigned(7 downto 0);
	b           : out unsigned(7 downto 0);

	-- cartridge port
	game        : in  std_logic;
	exrom       : in  std_logic;
	ioE_rom     : in  std_logic;
	ioF_rom     : in  std_logic;
	max_ram     : in  std_logic;
	irq_n       : in  std_logic;
	nmi_n       : in  std_logic;
	nmi_ack     : out std_logic;
	romL        : out std_logic;
	romH        : out std_logic;
	UMAXromH 	: out std_logic;
	IOE			: out std_logic;
	IOF			: out std_logic;
	freeze_key  : out std_logic;
	mod_key     : out std_logic;

	ioF_ext     : in  std_logic;
	ioE_ext     : in  std_logic;
	io_data     : in  unsigned(7 downto 0);

	-- joystick interface
	joyA        : in  std_logic_vector(6 downto 0);
	joyB        : in  std_logic_vector(6 downto 0);
	pot1        : in  std_logic_vector(7 downto 0);
	pot2        : in  std_logic_vector(7 downto 0);
	pot3        : in  std_logic_vector(7 downto 0);
	pot4        : in  std_logic_vector(7 downto 0);

	--Connector to the SID
	audio_data  : out std_logic_vector(17 downto 0);
	sid_filter  : in  std_logic;
	sid_ver     : in  std_logic;
	sid_we_ext  : out std_logic;
	sid_mode    : in  std_logic_vector(1 downto 0);
	sid_cfg     : in  std_logic_vector(2 downto 0);
	sid_ld_clk  : in  std_logic;
	sid_ld_addr : in  std_logic_vector(11 downto 0);
	sid_ld_data : in  std_logic_vector(15 downto 0);
	sid_ld_wr   : in  std_logic;
	sid_ce      : out std_logic;
	
	-- USER
	pb_i        : in  unsigned(7 downto 0);
	pb_o        : out unsigned(7 downto 0);
	pa2_i       : in  std_logic;
	pa2_o       : out std_logic;
	pc2_n_o     : out std_logic;
	flag2_n_i   : in  std_logic;
	sp2_i       : in  std_logic;

	-- IEC
	iec_data_o	: out std_logic;
	iec_data_i	: in  std_logic;
	iec_clk_o	: out std_logic;
	iec_clk_i	: in  std_logic;
	iec_atn_o	: out std_logic;
	
	c64rom_addr : in  std_logic_vector(13 downto 0);
	c64rom_data : in  std_logic_vector(7 downto 0);
	c64rom_wr   : in  std_logic;

	cass_motor  : out std_logic;
	cass_write  : out std_logic;
	cass_sense  : in  std_logic;
	cass_in     : in  std_logic
);
end fpga64_sid_iec;

-- -----------------------------------------------------------------------

architecture rtl of fpga64_sid_iec is
-- System state machine
type sysCycleDef is (
	CYCLE_IDLE0, CYCLE_IDLE1, CYCLE_IDLE2, CYCLE_IDLE3,
	CYCLE_IDLE4, CYCLE_IDLE5, CYCLE_IDLE6, CYCLE_IDLE7,
	CYCLE_IEC0,  CYCLE_IEC1,  CYCLE_IEC2,  CYCLE_IEC3,
	CYCLE_VIC0,  CYCLE_VIC1,  CYCLE_VIC2,  CYCLE_VIC3,
	CYCLE_CPU0,  CYCLE_CPU1,  CYCLE_CPU2,  CYCLE_CPU3,
	CYCLE_CPU4,  CYCLE_CPU5,  CYCLE_CPU6,  CYCLE_CPU7,
	CYCLE_CPU8,  CYCLE_CPU9,  CYCLE_CPUA,  CYCLE_CPUB,
	CYCLE_CPUC,  CYCLE_CPUD,  CYCLE_CPUE,  CYCLE_CPUF
);

signal sysCycle     : sysCycleDef := sysCycleDef'low;
signal preCycle     : sysCycleDef := sysCycleDef'low;
signal sysEnable    : std_logic;

signal phi0_cpu     : std_logic;
signal cpuHasBus    : std_logic;

signal baLoc        : std_logic;
signal aec          : std_logic;

signal enableCpu    : std_logic;
signal enableVic    : std_logic;
signal enablePixel  : std_logic;
signal enableSid    : std_logic;

signal irq_cia1     : std_logic;
signal irq_cia2     : std_logic;
signal irq_vic      : std_logic;

signal systemWe     : std_logic;
signal pulseWr_io   : std_logic;
signal systemAddr   : unsigned(15 downto 0);

signal cs_vic       : std_logic;
signal cs_sid       : std_logic;
signal cs_color     : std_logic;
signal cs_cia1      : std_logic;
signal cs_cia2      : std_logic;
signal cs_ram       : std_logic;
signal cpuWe        : std_logic;
signal cpuAddr      : unsigned(15 downto 0);
signal cpuDi        : unsigned(7 downto 0);
signal cpuDo        : unsigned(7 downto 0);
signal cpuIO        : unsigned(7 downto 0);

signal io_enable    : std_logic;
signal cpu_cyc      : std_logic;
signal cpu_cyc_s    : std_logic_vector(1 downto 0);
signal turbo_m      : std_logic_vector(2 downto 0);
signal turbo_cnt    : integer range 0 to 9999;

signal reset        : std_logic := '1';

-- CIA signals
signal enableCia_p  : std_logic;
signal enableCia_n  : std_logic;
signal cia1Do       : unsigned(7 downto 0);
signal cia2Do       : unsigned(7 downto 0);
signal cia1_pai     : unsigned(7 downto 0);
signal cia1_pao     : unsigned(7 downto 0);
signal cia1_pbi     : unsigned(7 downto 0);
signal cia1_pbo     : unsigned(7 downto 0);
signal cia2_pai     : unsigned(7 downto 0);
signal cia2_pao     : unsigned(7 downto 0);
signal cia2_pbi     : unsigned(7 downto 0);
signal cia2_pbo     : unsigned(7 downto 0);

signal todclk       : std_logic;

-- video
signal vicColorIndex: unsigned(3 downto 0);
signal vicBus       : unsigned(7 downto 0);
signal vicDi        : unsigned(7 downto 0);
signal vicDiAec     : unsigned(7 downto 0);
signal vicAddr      : unsigned(15 downto 0);
signal vicData      : unsigned(7 downto 0);
signal lastVicDi    : unsigned(7 downto 0);
signal vicAddr1514  : unsigned(1 downto 0);
signal colorData    : unsigned(3 downto 0);
signal colorDataAec : unsigned(3 downto 0);
signal turbo_en     : std_logic;
signal turbo_state  : std_logic;

-- SID signals
signal sid_do       : unsigned(7 downto 0);
signal sid_do_int   : unsigned(7 downto 0);
signal sid_we       : std_logic;
signal sid_sel_int  : std_logic;
signal pot_x1       : std_logic_vector(7 downto 0);
signal pot_y1       : std_logic_vector(7 downto 0);
signal pot_x2       : std_logic_vector(7 downto 0);
signal pot_y2       : std_logic_vector(7 downto 0);

component sid_top
	port (
		reset         : in  std_logic;
		clk           : in  std_logic;
		ce_1m         : in  std_logic;
		we            : in  std_logic;
		addr          : in  unsigned(4 downto 0);
		data_in       : in  unsigned(7 downto 0);
		data_out      : out unsigned(7 downto 0);
		pot_x         : in  std_logic_vector(7 downto 0);
		pot_y         : in  std_logic_vector(7 downto 0);
		audio_data    : out std_logic_vector(17 downto 0);
		filter_en     : in  std_logic;

		mode          : in  std_logic;
		cfg           : in  std_logic_vector(2 downto 0);
		ld_clk        : in  std_logic;
		ld_addr       : in  std_logic_vector(11 downto 0);
		ld_data       : in  std_logic_vector(15 downto 0);
		ld_wr         : in  std_logic
  );
end component;

component mos6526
	PORT (
		clk           : in  std_logic;
		mode          : in  std_logic := '0'; -- 0 - 6526 "old", 1 - 8521 "new"
		phi2_p        : in  std_logic;
		phi2_n        : in  std_logic;
		res_n         : in  std_logic;
		cs_n          : in  std_logic;
		rw            : in  std_logic; -- '1' - read, '0' - write
		rs            : in  unsigned(3 downto 0);
		db_in         : in  unsigned(7 downto 0);
		db_out        : out unsigned(7 downto 0);
		pa_in         : in  unsigned(7 downto 0);
		pa_out        : out unsigned(7 downto 0);
		pb_in         : in  unsigned(7 downto 0);
		pb_out        : out unsigned(7 downto 0);
		flag_n        : in  std_logic;
		pc_n          : out std_logic;
		tod           : in  std_logic;
		sp_in         : in  std_logic;
		sp_out        : out std_logic;
		cnt_in        : in  std_logic;
		cnt_out       : out std_logic;
		irq_n         : out std_logic
	);
end component; 

begin

-- -----------------------------------------------------------------------
-- Local signal to outside world
-- -----------------------------------------------------------------------

io_cycle <= '1' when
	(sysCycle >= CYCLE_IDLE0 and sysCycle <= CYCLE_IDLE3) or
	(sysCycle >= CYCLE_IEC0  and sysCycle <= CYCLE_IEC3)  else '0';

refresh <= '1' when preCycle = CYCLE_IDLE4 else '0';

-- -----------------------------------------------------------------------
-- System state machine, controls bus accesses
-- and triggers enables of other components
-- -----------------------------------------------------------------------

sysCycle <= preCycle when sysEnable = '1' else CYCLE_IDLE4;
pause_out <= not sysEnable;

process(clk32)
begin
	if rising_edge(clk32) then
		if preCycle = sysCycleDef'high then
			preCycle <= sysCycleDef'low;
		else
			preCycle <= sysCycleDef'succ(preCycle);
		end if;
		
		if preCycle = CYCLE_IDLE4 then
			sysEnable <= not pause;
		end if;
	end if;
end process;

process(clk32)
begin
	if rising_edge(clk32) then
		if preCycle = sysCycleDef'high then
			reset <= not reset_n;
		end if;
	end if;
end process;

-- PHI0/2-clock emulation
process(clk32)
begin
	if rising_edge(clk32) then
		if sysCycle = sysCycleDef'pred(CYCLE_CPU0) then
			phi0_cpu <= '1';
			if baLoc = '1' or cpuWe = '1' then
				cpuHasBus <= '1';
			end if;
		end if;
		if sysCycle = sysCycleDef'high then
			phi0_cpu <= '0';
			cpuHasBus <= '0';
		end if;
	end if;
end process;

process(clk32)
begin
	if rising_edge(clk32) then
		enableVic <= '0';
		enableCia_n <= '0';
		enableCia_p <= '0';
		enableSid <= '0';

		case sysCycle is
		when CYCLE_VIC2 =>
			enableVic <= '1';
		when CYCLE_CPUE =>
			enableVic <= '1';
		when CYCLE_CPUC =>
			enableCia_n <= '1';
		when CYCLE_CPUF =>
			enableCia_p <= '1';
			enableSid <= '1';
		when others =>
			null;
		end case;
	end if;
end process;

-- -----------------------------------------------------------------------
-- Color RAM
-- -----------------------------------------------------------------------
colorram: entity work.spram
generic map (
	DATA_WIDTH => 4,
	ADDR_WIDTH => 10
)
port map (
	clk => clk32,
	we => cs_color and pulseWr_io,
	addr => systemAddr(9 downto 0),
	data => cpuDo(3 downto 0),
	q => colorData
);

-- -----------------------------------------------------------------------
-- PLA and bus-switches
-- -----------------------------------------------------------------------
buslogic: entity work.fpga64_buslogic
port map (
	clk => clk32,
	reset => reset,
	bios => bios,

	cpuHasBus => cpuHasBus,
	aec => aec,

	bankSwitch => cpuIO(2 downto 0),

	game => game,
	exrom => exrom,
	ioE_rom => ioE_rom,
	ioF_rom => ioF_rom,
	max_ram => max_ram,

	ramData => ramDin,

	ioF_ext => ioF_ext,
	ioE_ext => ioE_ext,
	io_data => io_data,

	cpuWe => cpuWe,
	cpuAddr => cpuAddr,
	cpuData => cpuDo,
	vicAddr => vicAddr,
	vicData => vicData,
	sidData => sid_do,
	colorData => colorData,
	cia1Data => cia1Do,
	cia2Data => cia2Do,
	lastVicData => lastVicDi,

	systemWe => systemWe,
	systemAddr => systemAddr,
	dataToCpu => cpuDi,
	dataToVic => vicDi,

	io_enable => io_enable,

	cs_vic => cs_vic,
	cs_sid => cs_sid,
	cs_color => cs_color,
	cs_cia1 => cs_cia1,
	cs_cia2 => cs_cia2,
	cs_ram => cs_ram,
	cs_ioE => IOE,
	cs_ioF => IOF,
	cs_romL => romL,
	cs_romH => romH,
	cs_UMAXromH => UMAXromH,

	c64rom_addr => c64rom_addr,
	c64rom_data => c64rom_data,
	c64rom_wr => c64rom_wr
);

process(clk32)
begin
	if rising_edge(clk32) then
		pulseWr_io <= '0';
		if cpuWe = '1' then
			if sysCycle = CYCLE_CPUC then
				pulseWr_io <= '1';
			end if;
		end if;
	end if;
end process;

-- -----------------------------------------------------------------------
-- VIC-II video interface chip
-- -----------------------------------------------------------------------
process(clk32)
begin
	if rising_edge(clk32) then
		if phi0_cpu = '1' then
			if cpuWe = '1' and cs_vic = '1' then
				vicBus <= cpuDo;
			else
				vicBus <= x"FF";
			end if;
		end if;
	end if;
end process;

-- In the first three cycles after BA went low, the VIC reads
-- $ff as character pointers and
-- as color information the lower 4 bits of the opcode after the access to $d011.
vicDiAec <= vicBus when aec = '0' else vicDi;
colorDataAec <= cpuDi(3 downto 0) when aec = '0' else colorData;

vic: entity work.video_vicii_656x
generic map (
	registeredAddress => false,
	emulateRefresh => true,
	emulateLightpen => true,
	emulateGraphics => true
)			
port map (
	clk => clk32,
	reset => reset,
	enaPixel => enablePixel,
	enaData => enableVic,
	phi => phi0_cpu,
	
	baSync => '0',
	ba => baLoc,

	mode6569 => (not ntscMode),
	mode6567old => '0',
	mode6567R8 => ntscMode,
	mode6572 => '0',
	
	turbo_en => turbo_en,
	turbo_state => turbo_state,
	
	cs => cs_vic,
	we => cpuWe,
	lp_n => cia1_pbi(4),

	aRegisters => cpuAddr(5 downto 0),
	diRegisters => cpuDo,
	di => vicDiAec,
	diColor => colorDataAec,
	do => vicData,

	vicAddr => vicAddr(13 downto 0),
	addrValid => aec,
	
	hsync => hSync,
	vsync => vSync,
	colorIndex => vicColorIndex,

	irq_n => irq_vic
);

c64colors: entity work.fpga64_rgbcolor
port map (
	index => vicColorIndex,
	r => r,
	g => g,
	b => b
);

process(clk32)
begin
	if rising_edge(clk32) then
		if sysCycle = CYCLE_VIC3 then
			lastVicDi <= vicDi;
		end if;
	end if;
end process;

-- VIC bank to address lines
-- 
-- The glue logic on a C64C will generate a glitch during 10 <-> 01
-- generating 00 (in other words, bank 3) for one cycle.
--
-- When using the data direction register to change a single bit 0->1
-- (in other words, decreasing the video bank number by 1 or 2),
-- the bank change is delayed by one cycle. This effect is unstable.
process(clk32)
begin
	if rising_edge(clk32) then
		if phi0_cpu = '0' and enableVic = '1' then
			vicAddr1514 <= not cia2_pao(1 downto 0);
		end if;
	end if;
end process;

-- emulate only the first glitch (enough for Undead from Emulamer)
vicAddr(15 downto 14) <= "11" when ((vicAddr1514 xor not cia2_pao(1 downto 0)) = "11") and (cia2_pao(0) /= cia2_pao(1)) else not unsigned(cia2_pao(1 downto 0));

-- Pixel timing
process(clk32)
begin
	if rising_edge(clk32) then
		enablePixel <= '0';
		if sysCycle = CYCLE_VIC2
		or sysCycle = CYCLE_IDLE2
		or sysCycle = CYCLE_IDLE6
		or sysCycle = CYCLE_IEC2
		or sysCycle = CYCLE_CPU2
		or sysCycle = CYCLE_CPU6
		or sysCycle = CYCLE_CPUA
		or sysCycle = CYCLE_CPUE then
			enablePixel <= '1';
		end if;
	end if;
end process;

-- -----------------------------------------------------------------------
-- SID
-- -----------------------------------------------------------------------

sid_we      <= pulseWr_io and cs_sid;
sid_sel_int <= not sid_mode(1) or (not sid_mode(0) and not cpuAddr(5)) or (sid_mode(0) and not cpuAddr(8));
sid_we_ext  <= sid_we and (not sid_mode(1) or not sid_sel_int);
sid_do      <= io_data when sid_sel_int = '0' else sid_do_int;
sid_ce      <= enableSid;

pot_x1 <= (others => '1' ) when cia1_pao(6) = '0' else not pot1;
pot_y1 <= (others => '1' ) when cia1_pao(6) = '0' else not pot2;
pot_x2 <= (others => '1' ) when cia1_pao(7) = '0' else not pot3;
pot_y2 <= (others => '1' ) when cia1_pao(7) = '0' else not pot4;

sid : sid_top
port map (
	reset => reset,
	clk => clk32,
	ce_1m => enableSid,
	we => sid_we and sid_sel_int,
	addr => cpuAddr(4 downto 0),
	data_in => cpuDo,
	data_out => sid_do_int,
	pot_x => pot_x1 and pot_x2,
	pot_y => pot_y1 and pot_y2,
	audio_data => audio_data,
	filter_en => sid_filter,

	mode    => sid_ver,
	cfg     => sid_cfg,
	ld_clk  => sid_ld_clk,
	ld_addr => sid_ld_addr,
	ld_data => sid_ld_data,
	ld_wr   => sid_ld_wr
);

-- -----------------------------------------------------------------------
-- CIAs
-- -----------------------------------------------------------------------
cia1: mos6526
port map (
	clk => clk32,
	mode => cia_mode,
	phi2_p => enableCia_p,
	phi2_n => enableCia_n,
	res_n => not reset,
	cs_n => not cs_cia1,
	rw => not cpuWe,

	rs => cpuAddr(3 downto 0),
	db_in => cpuDo,
	db_out => cia1Do,

	pa_in => cia1_pai,
	pa_out => cia1_pao,
	pb_in => cia1_pbi,
	pb_out => cia1_pbo,

	flag_n => cass_in,
	sp_in => '1',
	cnt_in => '1',

	tod => todclk,

	irq_n => irq_cia1
);

cia2: mos6526
port map (
	clk => clk32,
	mode => cia_mode,
	phi2_p => enableCia_p,
	phi2_n => enableCia_n,
	res_n => not reset,
	cs_n => not cs_cia2,
	rw => not cpuWe,

	rs => cpuAddr(3 downto 0),
	db_in => cpuDo,
	db_out => cia2Do,

	pa_in => cia2_pai and cia2_pao,
	pa_out => cia2_pao,
	pb_in => pb_i and cia2_pbo,
	pb_out => cia2_pbo,

	flag_n => flag2_n_i,
	pc_n => pc2_n_o,

	sp_in => sp2_i,
	cnt_in => '1',

	tod => todclk,

	irq_n => irq_cia2
);

serialBus: process(clk32)
begin
	if rising_edge(clk32) then
		if sysCycle = CYCLE_IEC1 then
			cia2_pai(7) <= iec_data_i and not cia2_pao(5);
			cia2_pai(6) <= iec_clk_i and not cia2_pao(4);
		end if;
	end if;
end process;

cia2_pai(5 downto 0) <= "111" & pa2_i & "11";

iec_data_o <= not cia2_pao(5);
iec_clk_o  <= not cia2_pao(4);
iec_atn_o  <= not cia2_pao(3);

pb_o  <= cia2_pbo;
pa2_o <= cia2_pao(2);

process(clk32)
variable sum: integer range 0 to 33000000;
begin
	if rising_edge(clk32) then
		if reset = '1' then
			todclk <= '0';
			sum := 0;
		elsif ntscMode = '1' then
			sum := sum + 120;
			if sum >= 32727266 then
				sum := sum - 32727266;
				todclk <= not todclk;
			end if;
		else
			sum := sum + 100;
			if sum >= 31527954 then
				sum := sum - 31527954;
				todclk <= not todclk;
			end if;
		end if;
	end if;
end process;

-- -----------------------------------------------------------------------
-- 6510 CPU
-- -----------------------------------------------------------------------
cpu: entity work.cpu_6510
port map (
	clk => clk32,
	reset => reset,
	enable => enableCpu,
	nmi_n => irq_cia2 and nmi_n,
	nmi_ack => nmi_ack,
	irq_n => irq_cia1 and irq_vic and irq_n,
	rdy => baLoc,

	di => cpuDi,
	addr => cpuAddr,
	do => cpuDo,
	we => cpuWe,

	diIO => cpuIO(7) & cpuIO(6) & cpuIO(5) & cass_sense & cpuIO(3) & "111",
	doIO => cpuIO
);

cass_motor <= cpuIO(5);
cass_write <= cpuIO(3);

ramDout <= cpuDo;
ramAddr <= systemAddr;
ramWE   <= systemWe when sysCycle >= CYCLE_CPU0 else '0';
ramCE   <= cs_ram when sysCycle = CYCLE_VIC0 or cpu_cyc = '1' else '0';
cpu_cyc <= '1' when 
				(sysCycle = CYCLE_CPU0 and turbo_m(0) = '1' and cs_ram = '1' ) or
				(sysCycle = CYCLE_CPU4 and turbo_m(1) = '1' and cs_ram = '1' ) or
				(sysCycle = CYCLE_CPU8 and turbo_m(2) = '1' and cs_ram = '1' ) or
				(sysCycle = CYCLE_CPUC and (io_enable = '1'  or cs_ram = '1')) else '0';
				
process(clk32)
begin
	if rising_edge(clk32) then
		cpu_cyc_s <= cpu_cyc_s(0) & cpu_cyc;
		enableCpu <= cpu_cyc_s(1);
		io_enable <= io_enable and not enableCpu;

		if sysCycle = CYCLE_IDLE0 then

			io_enable <= '1';

			if turbo_cnt /= 0 then
				turbo_cnt <= turbo_cnt - 1;
			end if;

			turbo_en <= turbo_mode(0);
			turbo_m <= "000";
			if (turbo_mode(0) and turbo_state) = '1' or (turbo_mode(1) = '1' and turbo_cnt = 0) then
				case turbo_speed is
					when "00" => turbo_m <= "010";
					when "01" => turbo_m <= "110";
					when "10" => turbo_m <= "111";
					when "11" => turbo_m <= "111"; -- unused
				end case;
			end if;
		end if;

		if turbo_reset = '1' then
			turbo_cnt <= 9999;
		end if;
	end if;
end process;

-- -----------------------------------------------------------------------
-- Keyboard
-- -----------------------------------------------------------------------
Keyboard: entity work.fpga64_keyboard
port map (
	clk => clk32,
	
	reset => kbd_reset,
	ps2_key => ps2_key,

	joyA => not unsigned(joyA(4 downto 0)),
	joyB => not unsigned(joyB(4 downto 0)),
	pai => cia1_pao,
	pbi => cia1_pbo,
	pao => cia1_pai,
	pbo => cia1_pbi,

	restore_key => freeze_key,
	mod_key => mod_key,
	backwardsReadingEnabled => '1'
);

end architecture;
