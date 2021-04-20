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
--
-- C64 palette index to 24 bit RGB color
-- 
-- -----------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.all;

-- -----------------------------------------------------------------------

entity fpga64_rgbcolor is
	port (
		index: in unsigned(3 downto 0);
		r: out unsigned(7 downto 0);
		g: out unsigned(7 downto 0);
		b: out unsigned(7 downto 0)
	);
end fpga64_rgbcolor;

-- -----------------------------------------------------------------------

architecture Behavioral of fpga64_rgbcolor is
begin
	process(index)
	begin
		case index is
		 when X"0" => r <= X"00"; g <= X"00"; b <= X"00";
		 when X"1" => r <= X"FF"; g <= X"FF"; b <= X"FF";
		 when X"2" => r <= X"96"; g <= X"28"; b <= X"2E";
		 when X"3" => r <= X"5B"; g <= X"D6"; b <= X"CE";
		 when X"4" => r <= X"9F"; g <= X"2D"; b <= X"AD";
		 when X"5" => r <= X"41"; g <= X"B9"; b <= X"36";
		 when X"6" => r <= X"27"; g <= X"24"; b <= X"C4";
		 when X"7" => r <= X"EF"; g <= X"F3"; b <= X"47";
		 when X"8" => r <= X"9F"; g <= X"48"; b <= X"15";
		 when X"9" => r <= X"5E"; g <= X"35"; b <= X"00";
		 when X"A" => r <= X"DA"; g <= X"5F"; b <= X"66";
		 when X"B" => r <= X"47"; g <= X"47"; b <= X"47";
		 when X"C" => r <= X"78"; g <= X"78"; b <= X"78";
		 when X"D" => r <= X"91"; g <= X"FF"; b <= X"84";
		 when X"E" => r <= X"68"; g <= X"64"; b <= X"FF";
		 when X"F" => r <= X"AE"; g <= X"AE"; b <= X"AE";

end case;
end process;
end Behavioral;
