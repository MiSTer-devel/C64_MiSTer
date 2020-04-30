library IEEE;
use IEEE.std_logic_1164.all;

package C1541 is 

component c1541_sd is
port
(
	-- clk_c1541 ports
	clk_c1541      : in  std_logic;

	disk_change    : in  std_logic;
	disk_readonly  : in  std_logic;
	drive_num      : in  std_logic_vector(1 downto 0) := "00";
	led            : out std_logic;

	iec_reset_i    : in  std_logic;
	iec_atn_i      : in  std_logic;
	iec_data_i     : in  std_logic;
	iec_clk_i      : in  std_logic;
	iec_data_o     : out std_logic;
	iec_clk_o      : out std_logic;

	-- clk_sys ports
	clk_sys        : in  std_logic;

	sd_lba         : out std_logic_vector(31 downto 0);
	sd_rd          : out std_logic;
	sd_wr          : out std_logic;
	sd_ack         : in  std_logic;
	sd_buff_addr   : in  std_logic_vector(8 downto 0);
	sd_buff_dout   : in  std_logic_vector(7 downto 0);
	sd_buff_din    : out std_logic_vector(7 downto 0);
	sd_buff_wr     : in  std_logic;

	rom_addr       : in  std_logic_vector(13 downto 0) := (others => '0');
	rom_data       : in  std_logic_vector(7 downto 0) := (others => '0');
	rom_wr         : in  std_logic := '0';
	rom_std        : in  std_logic := '0'
);
end component;

end;
