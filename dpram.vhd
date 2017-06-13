library ieee;
use IEEE.std_logic_1164.all;
use IEEE.std_logic_unsigned.ALL;
use IEEE.numeric_std.all;

entity dpram is

	generic 
	(
		DATA_WIDTH : natural := 8;
		ADDR_WIDTH : natural := 16
	);

	port 
	(
		clk		: in  std_logic;
		addr_a	: in  unsigned((ADDR_WIDTH - 1) downto 0);
		addr_b	: in  unsigned((ADDR_WIDTH - 1) downto 0);
		data_a	: in  unsigned((DATA_WIDTH - 1) downto 0);
		data_b	: in  unsigned((DATA_WIDTH - 1) downto 0);
		q_a		: out unsigned((DATA_WIDTH - 1) downto 0);
		q_b		: out unsigned((DATA_WIDTH - 1) downto 0);
		we_a	   : in  std_logic := '0';
		we_b	   : in  std_logic := '0'
	);

end dpram;

architecture rtl of dpram is

	subtype word_t is unsigned((DATA_WIDTH-1) downto 0);
	type memory_t is array(2**ADDR_WIDTH-1 downto 0) of word_t;

	shared variable ram : memory_t;

begin

	-- Port A
	process(clk)
	begin
	if(rising_edge(clk)) then 
		if(we_a = '1') then
			ram(to_integer(addr_a)) := data_a;
			q_a <= data_a;
		else
			q_a <= ram(to_integer(addr_a));
		end if;
	end if;
	end process;

	-- Port B 
	process(clk)
	begin
	if(rising_edge(clk)) then 
		if(we_b = '1') then
			ram(to_integer(addr_b)) := data_b;
			q_b <= data_b;
		else
			q_b <= ram(to_integer(addr_b));
		end if;
	end if;
	end process;

end rtl;
