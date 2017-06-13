---------------------------------------------------------------------------------
-- Commodore 1541 to SD card (read only) by Dar (darfpga@aol.fr) 02-April-2015
-- http://darfpga.blogspot.fr
--
-- c1541_sd reads D64 data from raw SD card, produces GCR data, feeds c1541_logic
-- Raw SD data : each D64 image must start on 256KB boundaries
-- disk_num allow to select D64 image
--
-- c1541_logic    from : Mark McDougall
-- spi_controller from : Michel Stempin, Stephen A. Edwards
-- via6522        from : Arnim Laeuger, Mark McDougall, MikeJ
--
-- c1541_logic    modified for : slow down CPU (EOI ack missed by real c64)
--                             : remove iec internal OR wired
--                             : synched atn_in (sometime no IRQ with real c64)
-- spi_controller modified for : sector start and size adapted + busy signal
-- via6522        modified for : no modification
--
--
-- Input clk 32MHz
--
---------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.std_logic_unsigned.ALL;
use IEEE.numeric_std.all;

entity c1541_sd is
port
(
	clk32          : in std_logic;
	reset          : in std_logic;

	disk_change    : in std_logic;

	iec_atn_i      : in std_logic;
	iec_data_i     : in std_logic;
	iec_clk_i      : in std_logic;

	iec_atn_o      : out std_logic;
	iec_data_o     : out std_logic;
	iec_clk_o      : out std_logic;

	sd_lba         : out std_logic_vector(31 downto 0);
	sd_rd          : out std_logic;
	sd_wr          : out std_logic;
	sd_ack         : in  std_logic;

	sd_buff_addr   : in  std_logic_vector(8 downto 0);
	sd_buff_dout   : in  std_logic_vector(7 downto 0);
	sd_buff_din    : out std_logic_vector(7 downto 0);
	sd_buff_wr     : in  std_logic;

	led            : out std_logic;

	c1541rom_addr  : in  std_logic_vector(13 downto 0);
	c1541rom_data  : in  std_logic_vector(7 downto 0);
	c1541rom_wr    : in  std_logic
);
end c1541_sd;

architecture struct of c1541_sd is

	component sd_card port
	(
		sd_lba         : out std_logic_vector(31 downto 0);
		sd_rd          : out std_logic;
		sd_wr          : out std_logic;
		sd_ack         : in  std_logic;

		sd_buff_addr   : in  std_logic_vector(8 downto 0);
		sd_buff_dout   : in  std_logic_vector(7 downto 0);
		sd_buff_din    : out std_logic_vector(7 downto 0);
		sd_buff_wr     : in  std_logic;

		buff_addr      : in  std_logic_vector(7 downto 0);
		buff_dout      : out std_logic_vector(7 downto 0);
		buff_din       : in  std_logic_vector(7 downto 0);
		buff_we        : in  std_logic;

		change         : in  std_logic;                     -- Force reload as disk may have changed
		track          : in  std_logic_vector(5 downto 0);  -- Track number (0-34)
		sector         : in  std_logic_vector(4 downto 0);  -- Sector number (0-20)
		busy           : out std_logic;

		clk            : in  std_logic;     -- System clock
		reset          : in  std_logic
	);
	end component sd_card;

	signal buff_dout  : std_logic_vector(7 downto 0);
	signal do         : std_logic_vector(7 downto 0); -- disk read data
	--signal mode       : std_logic;                    -- read/write
	signal stp        : std_logic_vector(1 downto 0); -- stepper motor control
	signal mtr        : std_logic ;                   -- stepper motor on/off
	signal sync_n     : std_logic;                    -- reading SYNC bytes
	signal byte_n     : std_logic;                    -- byte ready
	signal act        : std_logic;                    -- activity LED
	signal sd_busy    : std_logic;
	signal track      : std_logic_vector(5 downto 0);
	signal sector     : std_logic_vector(4 downto 0);
	signal byte_addr  : std_logic_vector(7 downto 0);

begin
	
	c1541 : entity work.c1541_logic
	generic map
	(
		DEVICE_SELECT => "00"
	)
	port map
	(
		clk_32M => clk32,
		reset => reset,

		-- serial bus
		sb_data_oe => iec_data_o,
		sb_clk_oe  => iec_clk_o,
		sb_atn_oe  => iec_atn_o,
		
		sb_data_in => not iec_data_i,
		sb_clk_in  => not iec_clk_i,
		sb_atn_in  => not iec_atn_i,
    
		c1541rom_addr => c1541rom_addr,
		c1541rom_data => c1541rom_data,
		c1541rom_wr   => c1541rom_wr,

		-- drive-side interface
		ds            => "00",   -- device select
		di            => do,     -- disk read data
		do            => open,   -- disk write data
		mode          => open, --mode,   -- read/write
		stp           => stp,    -- stepper motor control
		mtr           => mtr,    -- motor on/off
		freq          => open,   -- motor frequency
		sync_n        => sync_n, -- reading SYNC bytes
		byte_n        => byte_n, -- byte ready
		wps_n         => '0',    -- write-protect sense
		tr00_sense_n  => '1',    -- track 0 sense (unused?)
		act           => act     -- activity LED
	);

	floppy : entity work.gcr_floppy
	port map
	(
		clk32  => clk32,
		reset  => reset,

		do     => do,     -- disk read data
		stp    => stp,    -- stepper motor control
		mtr    => mtr,    -- stepper motor on/off
		sync_n => sync_n, -- reading SYNC bytes
		byte_n => byte_n, -- byte ready
		
		track       => track,
		sector      => sector,
		byte_addr   => byte_addr,
		track_din   => buff_dout,
		track_ready => not sd_busy
	);

	sd : sd_card
	port map
	(
		sd_lba  => sd_lba,
		sd_rd   => sd_rd,
		sd_wr   => sd_wr,
		sd_ack  => sd_ack,

		sd_buff_addr => sd_buff_addr,
		sd_buff_dout => sd_buff_dout,
		sd_buff_din  => sd_buff_din,
		sd_buff_wr   => sd_buff_wr,

		buff_addr => byte_addr,
		buff_dout => buff_dout,
		buff_din  => (others => '0'),
		buff_we   => '0',

		change  => disk_change,
		track   => track,
		sector  => sector,

		clk     => clk32,
		reset   => reset, 
		busy    => sd_busy
	);

	led <= act or sd_busy;
end struct;
