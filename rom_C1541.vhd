library ieee;
use IEEE.std_logic_1164.all;
use IEEE.std_logic_unsigned.ALL;
use IEEE.numeric_std.all;

entity rom_c1541 is

	generic 
	(
		DATA_WIDTH : natural := 8;
		ADDR_WIDTH : natural := 14
	);

	port 
	(
		clock	    : in  std_logic;
		wraddress : in  std_logic_vector((ADDR_WIDTH - 1) downto 0);
		rdaddress : in  std_logic_vector((ADDR_WIDTH - 1) downto 0);
		data	    : in  std_logic_vector((DATA_WIDTH - 1) downto 0);
		q         : out std_logic_vector((DATA_WIDTH - 1) downto 0);
		wren      : in  std_logic := '0'
	);

end rom_c1541;

architecture rtl of rom_c1541 is

	subtype word_t is std_logic_vector((DATA_WIDTH-1) downto 0);
	type memory_t is array(2**ADDR_WIDTH-1 downto 0) of word_t;

	shared variable ram : memory_t;
	
	attribute ram_init_file : string;
	attribute ram_init_file of ram : variable is "roms/std_C1541.mif";	

begin

	-- Port A
	process(clock)
	begin
	if(rising_edge(clock)) then 
		if(wren = '1') then
			ram(to_integer(unsigned(wraddress))) := data;
		end if;
	end if;
	end process;

	-- Port B 
	process(clock)
	begin
	if(rising_edge(clock)) then 
  	    q <= ram(to_integer(unsigned(rdaddress)));
	end if;
	end process;

end rtl;
