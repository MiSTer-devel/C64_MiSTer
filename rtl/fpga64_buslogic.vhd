-- -----------------------------------------------------------------------
--
--                                 FPGA 64
--
--     A fully functional commodore 64 implementation in a single FPGA
--
-- -----------------------------------------------------------------------
-- Copyright 2005-2008 by Peter Wendrich (pwsoft@syntiac.com)
-- http://www.syntiac.com/fpga64.html
-- -----------------------------------------------------------------------

-- -----------------------------------------------------------------------
-- Dar 08/03/2014
--
-- Based on mixing both fpga64_buslogic_roms and fpga64_buslogic_nommu
-- RAM should be external SRAM
-- Basic, Char and Kernel ROMs are included
-- Original Kernel replaced by JiffyDos
-- -----------------------------------------------------------------------

library IEEE;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

entity fpga64_buslogic is
	port (
		clk         : in std_logic;
		reset       : in std_logic;
		bios        : in std_logic_vector(1 downto 0);

		cpuHasBus   : in std_logic;
		aec         : in std_logic;

		ramData     : in unsigned(7 downto 0);

		-- 2 CHAREN
		-- 1 HIRAM
		-- 0 LORAM
		bankSwitch  : in unsigned(2 downto 0);

		-- From cartridge port
		game        : in std_logic;
		exrom       : in std_logic;
		io_rom      : in std_logic;
		io_ext      : in std_logic;
		io_data     : in unsigned(7 downto 0);

		c64rom_addr : in std_logic_vector(13 downto 0);
		c64rom_data : in std_logic_vector(7 downto 0);
		c64rom_wr   : in std_logic;

		cpuWe       : in std_logic;
		cpuAddr     : in unsigned(15 downto 0);
		cpuData     : in unsigned(7 downto 0);
		vicAddr     : in unsigned(15 downto 0);
		vicData     : in unsigned(7 downto 0);
		sidData     : in unsigned(7 downto 0);
		colorData   : in unsigned(3 downto 0);
		cia1Data    : in unsigned(7 downto 0);
		cia2Data    : in unsigned(7 downto 0);
		lastVicData : in unsigned(7 downto 0);

		io_enable   : in std_logic;

		systemWe    : out std_logic;
		systemAddr  : out unsigned(15 downto 0);
		dataToCpu   : out unsigned(7 downto 0);
		dataToVic   : out unsigned(7 downto 0);

		cs_vic      : out std_logic;
		cs_sid      : out std_logic;
		cs_color    : out std_logic;
		cs_cia1     : out std_logic;
		cs_cia2     : out std_logic;
		cs_ram      : out std_logic;

		-- To catridge port
		cs_ioE      : out std_logic;
		cs_ioF      : out std_logic;
		cs_romL     : out std_logic;
		cs_romH     : out std_logic;
		cs_UMAXromH : out std_logic
	);
end fpga64_buslogic;

-- -----------------------------------------------------------------------

architecture rtl of fpga64_buslogic is
	signal charData       : std_logic_vector(7 downto 0);
	signal charData_std   : std_logic_vector(7 downto 0);
	signal charData_jap   : std_logic_vector(7 downto 0);
	signal romData        : std_logic_vector(7 downto 0);
	signal romData_c64    : std_logic_vector(7 downto 0);
	signal romData_c64std : std_logic_vector(7 downto 0);
	signal romData_c64gs  : std_logic_vector(7 downto 0);
	signal romData_c64jap : std_logic_vector(7 downto 0);
	signal c64gs_ena      : std_logic := '0';
	signal c64std_ena     : std_logic := '0';
	signal c64jap_ena     : std_logic := '0';

	signal cs_CharLoc     : std_logic;
	signal cs_romLoc      : std_logic;
	signal vicCharLoc     : std_logic;

	signal cs_ramLoc      : std_logic;
	signal cs_vicLoc      : std_logic;
	signal cs_sidLoc      : std_logic;
	signal cs_colorLoc    : std_logic;
	signal cs_cia1Loc     : std_logic;
	signal cs_cia2Loc     : std_logic;
	signal cs_ioELoc      : std_logic;
	signal cs_ioFLoc      : std_logic;
	signal cs_romLLoc     : std_logic;
	signal cs_romHLoc     : std_logic;
	signal cs_UMAXromHLoc : std_logic;
	signal cs_UMAXnomapLoc: std_logic;
	signal ultimax        : std_logic;

	signal currentAddr    : unsigned(15 downto 0);
	
begin
	chargen: entity work.dprom
	generic map ("rtl/roms/chargen.mif", 12)
	port map
	(
		wrclock => clk,
		rdclock => clk,

		rdaddress => std_logic_vector(currentAddr(11 downto 0)),
		q => charData_std
	);

	chargen_j: entity work.dprom
	generic map ("rtl/roms/chargenj.mif", 12)
	port map
	(
		wrclock => clk,
		rdclock => clk,

		rdaddress => std_logic_vector(currentAddr(11 downto 0)),
		q => charData_jap
	);

	kernel_c64gs: entity work.dprom
	generic map ("rtl/roms/std_C64GS.mif", 14)
	port map
	(
		wrclock => clk,
		rdclock => clk,

		rdaddress => std_logic_vector(cpuAddr(14) & cpuAddr(12 downto 0)),
		q => romData_c64gs
	);

	kernel_c64: entity work.dprom
	generic map ("rtl/roms/dol_C64.mif", 14)
	port map
	(
		wrclock => clk,
		rdclock => clk,

		wren => c64rom_wr,
		data => c64rom_data,
		wraddress => c64rom_addr,

		rdaddress => std_logic_vector(cpuAddr(14) & cpuAddr(12 downto 0)),
		q => romData_c64
	);

	kernel_c64std: entity work.dprom
	generic map ("rtl/roms/std_C64.mif", 14)
	port map
	(
		wrclock => clk,
		rdclock => clk,

		rdaddress => std_logic_vector(cpuAddr(14) & cpuAddr(12 downto 0)),
		q => romData_c64std
	);

	kernel_c64jap: entity work.dprom
	generic map ("rtl/roms/jap_C64.mif", 14)
	port map
	(
		wrclock => clk,
		rdclock => clk,

		rdaddress => std_logic_vector(cpuAddr(14) & cpuAddr(12 downto 0)),
		q => romData_c64jap
	);

	romData <= romData_c64jap when c64jap_ena = '1' else
				  romData_c64std when c64std_ena = '1' else
				  romData_c64gs  when c64gs_ena  = '1' else
				  romData_c64;

	charData <= charData_jap when c64jap_ena = '1' else charData_std;

	process(clk)
	begin
		if rising_edge(clk) then
			if reset = '1' then 
				c64gs_ena  <= bios(1);
				c64std_ena <= bios(0);
				c64jap_ena <= bios(1) and bios(0);
			end if;
		end if;
	end process;

	--
	--begin
	process(ramData, vicData, sidData, colorData,
           cia1Data, cia2Data, charData, romData,
			  cs_romHLoc, cs_romLLoc, cs_romLoc, cs_CharLoc,
			  cs_ramLoc, cs_vicLoc, cs_sidLoc, cs_colorLoc,
			  cs_cia1Loc, cs_cia2Loc, lastVicData,
			  cs_ioELoc, cs_ioFLoc,
			  io_rom, io_ext, io_data)
	begin
		-- If no hardware is addressed the bus is floating.
		-- It will contain the last data read by the VIC. (if a C64 is shielded correctly)
		dataToCpu <= lastVicData;
		if cs_CharLoc = '1' then	
			dataToCpu <= unsigned(charData);
		elsif cs_romLoc = '1' then	
			dataToCpu <= unsigned(romData);
		elsif cs_ramLoc = '1' then
			dataToCpu <= ramData;
		elsif cs_vicLoc = '1' then
			dataToCpu <= vicData;
		elsif cs_sidLoc = '1' then
			dataToCpu <= sidData;
		elsif cs_colorLoc = '1' then
			dataToCpu(3 downto 0) <= colorData;
		elsif cs_cia1Loc = '1' then
			dataToCpu <= cia1Data;
		elsif cs_cia2Loc = '1' then
			dataToCpu <= cia2Data;
		elsif cs_romLLoc = '1' then
			dataToCpu <= ramData;
		elsif cs_romHLoc = '1' then
			dataToCpu <= ramData;
		elsif cs_ioELoc = '1' and io_rom = '1' then
			dataToCpu <= ramData;
		elsif cs_ioFLoc = '1' and io_rom = '1' then
			dataToCpu <= ramData;
		elsif cs_ioELoc = '1' and io_ext = '1' then
			dataToCpu <= io_data;
		elsif cs_ioFLoc = '1' and io_ext = '1' then
			dataToCpu <= io_data;
		end if;
	end process;

	ultimax <= exrom and (not game);

	process(cpuHasBus, cpuAddr, ultimax, cpuWe, bankSwitch, exrom, game, aec, vicAddr)
	begin
		currentAddr <= (others => '1');
		systemWe <= '0';
		vicCharLoc <= '0';
		cs_CharLoc <= '0';
		cs_romLoc <= '0';
		cs_ramLoc <= '0';
		cs_vicLoc <= '0';
		cs_sidLoc <= '0';
		cs_colorLoc <= '0';
		cs_cia1Loc <= '0';
		cs_cia2Loc <= '0';
		cs_ioELoc <= '0';
		cs_ioFLoc <= '0';
		cs_romLLoc <= '0';
		cs_romHLoc <= '0';
		cs_UMAXromHLoc <= '0';		-- Ultimax flag for the VIC access - LCA
		cs_UMAXnomapLoc <= '0';

		if (cpuHasBus = '1') then
			-- The 6502 CPU has the bus.					
			currentAddr <= cpuAddr;
			case cpuAddr(15 downto 12) is
			when X"E" | X"F" =>
				if ultimax = '1' then
					-- pass cpuWe to cartridge. Cartridge must block writes if no RAM connected.
					cs_romHLoc <= '1';
				elsif cpuWe = '0' and bankSwitch(1) = '1' then
					-- Read kernal
					cs_romLoc <= '1';
				else
					-- 64Kbyte RAM layout
					cs_ramLoc <= '1';
				end if;
			when X"D" =>
				if ultimax = '0' and bankSwitch(1) = '0' and bankSwitch(0) = '0' then
					-- 64Kbyte RAM layout
					cs_ramLoc <= '1';
				elsif ultimax = '1' or bankSwitch(2) = '1' then
					case cpuAddr(11 downto 8) is
						when X"0" | X"1" | X"2" | X"3" =>
							cs_vicLoc <= '1';
						when X"4" | X"5" | X"6" | X"7" =>
							cs_sidLoc <= '1';
						when X"8" | X"9" | X"A" | X"B" =>
							cs_colorLoc <= '1';
						when X"C" =>
							cs_cia1Loc <= '1';
						when X"D" =>
							cs_cia2Loc <= '1';
						when X"E" =>
							cs_ioELoc <= '1';
						when X"F" =>
							cs_ioFLoc <= '1';
						when others =>
							null;
					end case;
				else
					-- I/O space turned off. Read from charrom or write to RAM.
					if cpuWe = '0' then
						  cs_CharLoc <= '1';
					else
						  cs_ramLoc <= '1';
					end if;
				end if;
			when X"A" | X"B" =>
				if ultimax = '1' then
					cs_UMAXnomapLoc <= '1';
				elsif exrom = '0' and game = '0' and bankSwitch(1) = '1' then
				  -- this case should write to both C64 RAM and Cart RAM (if RAM is connected)
					cs_romHLoc <= '1';
				elsif ultimax = '0' and cpuWe = '0' and bankSwitch(1) = '1' and bankSwitch(0) = '1' then
					-- Access basic rom
					-- May need turning off if kernal banked out LCA
					cs_romLoc <= '1';
				else
					cs_ramLoc <= '1';
				end if;
			when X"8" | X"9" =>
				if ultimax = '1' then
					-- pass cpuWe to cartridge. Cartridge must block writes if no RAM connected.
					cs_romLLoc <= '1';
				elsif exrom = '0' and bankSwitch(1) = '1' and bankSwitch(0) = '1' then
				  -- this case should write to both C64 RAM and Cart RAM (if RAM is connected)
					cs_romLLoc <= '1';
				else
					cs_ramLoc <= '1';
				end if;
			when X"0" =>
				cs_ramLoc <= '1';
			when others =>
				-- If not in Ultimax mode access ram
				if ultimax = '0' then
					cs_ramLoc <= '1';
				else
					cs_UMAXnomapLoc <= '1';
				end if;
			end case;

			systemWe <= cpuWe;
		else
			-- The VIC-II has the bus, but only when aec is asserted
			if aec = '1' then
				currentAddr <= vicAddr;
			else
				currentAddr <= cpuAddr;
			end if;

			if ultimax = '0' and vicAddr(14 downto 12)="001" then
				vicCharLoc <= '1';
			elsif ultimax = '1' and vicAddr(13 downto 12)="11" then
				-- ultimax mode changes vic addressing - LCA 
				cs_UMAXromHLoc <= '1';
			else
				cs_ramLoc <= '1';
			end if;
		end if;
	end process;

	cs_ram <= cs_ramLoc or cs_romLLoc or cs_romHLoc or cs_UMAXromHLoc or cs_UMAXnomapLoc or cs_CharLoc or cs_romLoc;
	cs_vic <= cs_vicLoc and io_enable;
	cs_sid <= cs_sidLoc and io_enable;
	cs_color <= cs_colorLoc and io_enable;
	cs_cia1 <= cs_cia1Loc and io_enable;
	cs_cia2 <= cs_cia2Loc and io_enable;
	cs_ioE <= cs_ioELoc and io_enable;
	cs_ioF <= cs_ioFLoc and io_enable;
	cs_romL <= cs_romLLoc;
	cs_romH <= cs_romHLoc;
	cs_UMAXromH <= cs_UMAXromHLoc;

	dataToVic  <= unsigned(charData) when vicCharLoc = '1' else ramData;
	systemAddr <= currentAddr;
end architecture;
