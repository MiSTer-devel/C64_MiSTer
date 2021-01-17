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
		when X"2" => r <= X"81"; g <= X"33"; b <= X"38";
		when X"3" => r <= X"75"; g <= X"CE"; b <= X"C8";
		when X"4" => r <= X"8E"; g <= X"3C"; b <= X"97";
		when X"5" => r <= X"56"; g <= X"AC"; b <= X"4D";
		when X"6" => r <= X"2E"; g <= X"2C"; b <= X"9B";
		when X"7" => r <= X"ED"; g <= X"F1"; b <= X"71";
		when X"8" => r <= X"8E"; g <= X"50"; b <= X"29";
		when X"9" => r <= X"55"; g <= X"38"; b <= X"00";
		when X"A" => r <= X"C4"; g <= X"6C"; b <= X"71";
		when X"B" => r <= X"4A"; g <= X"4A"; b <= X"4A";
		when X"C" => r <= X"7B"; g <= X"7B"; b <= X"7B";
		when X"D" => r <= X"A9"; g <= X"FF"; b <= X"9F";
		when X"E" => r <= X"70"; g <= X"6D"; b <= X"EB";
		when X"F" => r <= X"B2"; g <= X"B2"; b <= X"B2";
		end case;
	end process;
end Behavioral;
