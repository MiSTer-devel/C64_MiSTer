library IEEE;
use IEEE.std_logic_1164.all;

-- 
-- Dummy wrapper with 2 pros:
--
-- 1. compatible with both Verilog and VHDL instantiation
-- 2. has default non-Zero values for ports, so doesn't require to set them if not needed (works in Verilog too!)
--

entity C1581 is
generic
(
	PARPORT        : integer range 0 to 1 := 0;
	DUALROM        : integer range 0 to 1 := 1
);
port
(
	-- clk ports
	clk            : in  std_logic;
	ce             : in  std_logic := '1'; -- 16 MHz
	pause          : in  std_logic := '0';

	drive_num      : in  std_logic_vector(1 downto 0) := "00";
	act_led        : out std_logic;
	pwr_led        : out std_logic;

	iec_reset_i    : in  std_logic;
	iec_atn_i      : in  std_logic;
	iec_data_i     : in  std_logic;
	iec_clk_i      : in  std_logic;
	iec_data_o     : out std_logic;
	iec_clk_o      : out std_logic;

	-- fast serial clock
	iec_fclk_i     : in  std_logic := '1';
	iec_fclk_o     : out std_logic;

	-- parallel bus
	par_data_i     : in  std_logic_vector(7 downto 0) := (others => '1');
	par_stb_i      : in  std_logic := '1';
	par_data_o     : out std_logic_vector(7 downto 0);
	par_stb_o      : out std_logic;

	-- clk_sys ports
	clk_sys        : in  std_logic;

	img_mounted    : in  std_logic;
	img_size       : in  std_logic_vector(31 downto 0);
	img_readonly   : in  std_logic := '0';

	sd_lba         : out std_logic_vector(31 downto 0);
	sd_rd          : out std_logic;
	sd_wr          : out std_logic;
	sd_ack         : in  std_logic;
	sd_buff_addr   : in  std_logic_vector(8 downto 0);
	sd_buff_dout   : in  std_logic_vector(7 downto 0);
	sd_buff_din    : out std_logic_vector(7 downto 0);
	sd_buff_wr     : in  std_logic;

	rom_addr       : in  std_logic_vector(14 downto 0) := (others => '0');
	rom_data       : in  std_logic_vector(7 downto 0) := (others => '0');
	rom_wr         : in  std_logic := '0';
	rom_std        : in  std_logic := '0'
);
end;

architecture rtl of C1581 is
	component c1581_sd
	generic
	(
		PARPORT        : integer range 0 to 1 := 0;
		DUALROM        : integer range 0 to 1 := 1
	);
	port
	(
		clk            : in  std_logic;
		ce             : in  std_logic;
		pause          : in  std_logic;

		drive_num      : in  std_logic_vector(1 downto 0);
		act_led        : out std_logic;
		pwr_led        : out std_logic;

		iec_reset_i    : in  std_logic;
		iec_atn_i      : in  std_logic;
		iec_data_i     : in  std_logic;
		iec_clk_i      : in  std_logic;
		iec_fclk_i     : in  std_logic;
		iec_data_o     : out std_logic;
		iec_clk_o      : out std_logic;
		iec_fclk_o     : out std_logic;

		par_data_i     : in  std_logic_vector(7 downto 0) := (others => '1');
		par_stb_i      : in  std_logic := '1';
		par_data_o     : out std_logic_vector(7 downto 0);
		par_stb_o      : out std_logic;

		clk_sys        : in  std_logic;

		img_mounted    : in  std_logic;
		img_size       : in  std_logic_vector(31 downto 0);
		img_readonly   : in  std_logic;

		sd_lba         : out std_logic_vector(31 downto 0);
		sd_rd          : out std_logic;
		sd_wr          : out std_logic;
		sd_ack         : in  std_logic;
		sd_buff_addr   : in  std_logic_vector(8 downto 0);
		sd_buff_dout   : in  std_logic_vector(7 downto 0);
		sd_buff_din    : out std_logic_vector(7 downto 0);
		sd_buff_wr     : in  std_logic;

		rom_addr       : in  std_logic_vector(14 downto 0);
		rom_data       : in  std_logic_vector(7 downto 0);
		rom_wr         : in  std_logic;
		rom_std        : in  std_logic
	);
	end component;
begin

	c1581_inst : c1581_sd
	generic map(PARPORT,DUALROM)
	port map
	(
		clk           => clk          ,
		ce            => ce           ,
		pause         => pause        ,
		img_mounted   => img_mounted  ,
		img_size      => img_size     ,
		img_readonly  => img_readonly ,
		drive_num     => drive_num    ,
		pwr_led       => pwr_led      ,
		act_led       => act_led      ,
		iec_reset_i   => iec_reset_i  ,
		iec_atn_i     => iec_atn_i    ,
		iec_data_i    => iec_data_i   ,
		iec_clk_i     => iec_clk_i    ,
		iec_fclk_i    => iec_fclk_i   ,
		iec_data_o    => iec_data_o   ,
		iec_clk_o     => iec_clk_o    ,
		iec_fclk_o    => iec_fclk_o   ,
		par_data_i    => par_data_i   ,
		par_stb_i     => par_stb_i    ,
		par_data_o    => par_data_o   ,
		par_stb_o     => par_stb_o    ,
		clk_sys       => clk_sys      ,
		sd_lba        => sd_lba       ,
		sd_rd         => sd_rd        ,
		sd_wr         => sd_wr        ,
		sd_ack        => sd_ack       ,
		sd_buff_addr  => sd_buff_addr ,
		sd_buff_dout  => sd_buff_dout ,
		sd_buff_din   => sd_buff_din  ,
		sd_buff_wr    => sd_buff_wr   ,
		rom_addr      => rom_addr     ,
		rom_data      => rom_data     ,
		rom_wr        => rom_wr       ,
		rom_std       => rom_std
	);

end architecture;
