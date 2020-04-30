library ieee;
use IEEE.std_logic_1164.all;
use IEEE.std_logic_unsigned.ALL;
use IEEE.numeric_std.all;

entity spram is

	generic 
	(
		DATA_WIDTH : natural := 8;
		ADDR_WIDTH : natural := 10
	);

	port 
	(
		clk  : in  std_logic;
		addr : in  unsigned((ADDR_WIDTH - 1) downto 0);
		data : in  unsigned((DATA_WIDTH - 1) downto 0);
		q    : out unsigned((DATA_WIDTH - 1) downto 0);
		we   : in  std_logic := '0'
	);

end spram;

architecture rtl of spram is

	subtype word_t is unsigned((DATA_WIDTH-1) downto 0);
	type memory_t is array(2**ADDR_WIDTH-1 downto 0) of word_t;

	shared variable ram : memory_t;

begin

	process(clk)
	begin
	if(rising_edge(clk)) then 
		if(we = '1') then
			ram(to_integer(addr)) := data;
			q <= data;
		else
			q <= ram(to_integer(addr));
		end if;
	end if;
	end process;

end rtl;
