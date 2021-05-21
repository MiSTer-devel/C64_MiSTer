---------------------------------------------------------------------------------
-- composite_sync by Dar (darfpga@aol.fr)
-- http://darfpga.blogspot.fr
--
-- Generate composite sync and blank for tv mode from h/v syncs
--
---------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.std_logic_unsigned.all;
use IEEE.numeric_std.all;

entity video_sync is
port(
	clk32 : in std_logic;
	pause : in std_logic;
	hsync : in std_logic;
	vsync : in std_logic;
	ntsc  : in std_logic;
	wide  : in std_logic;
	hsync_out : out std_logic;
	vsync_out : out std_logic;
	hblank : out std_logic;
	vblank : out std_logic
);
end;

architecture struct of video_sync is

	signal clk_cnt : std_logic_vector(1 downto 0);
	signal vsync_r : std_logic;
	signal hsync_r : std_logic;
	signal hsync_r0 : std_logic;

begin

process(clk32)
	variable  dot_count : integer range 0 to 1023 := 0;
	variable line_count : integer range 0 to 511 := 0;
	variable line_reset : std_logic := '0';
	begin
	if falling_edge(clk32) then
		hsync_r0 <= hsync;
		if hsync_r0 = '0' and hsync = '1' then
			clk_cnt <= "11";
		else
			clk_cnt <= clk_cnt + '1';
		end if;
	end if;

	if rising_edge(clk32) then
		if clk_cnt = "00" and pause = '0' then
			vsync_r <= vsync;
			hsync_r <= hsync;

			if hsync_r = '0' and hsync = '1' then
				dot_count := 0;
				if line_reset = '1' then
					line_count := 0;
					line_reset := '0';
				else
					line_count := line_count + 1;
				end if;
			else
				dot_count := dot_count + 1;
			end if;

			if vsync_r = '0' and vsync = '1' then
				line_reset := '1';
			end if;
			
			if ntsc = '1' then
				if dot_count     = 054 then hsync_out <= '0'; end if;
				if dot_count     = 016 then hsync_out <= '1';
					if line_count = 000 then vsync_out <= '1'; end if;
					if line_count = 004 then vsync_out <= '0'; end if;
				end if;

				if line_count = 000 then vblank <= '1'; end if;
				if line_count = 013 then vblank <= '0'; end if;

				if wide = '0' then
					if dot_count  = 516 then hblank <= '1'; end if;
					if dot_count  = 112 then hblank <= '0'; end if;
				else
					if dot_count  = 496 then hblank <= '1'; end if;
					if dot_count  = 132 then hblank <= '0'; end if;
				end if;
			else
				if dot_count     = 048 then hsync_out <= '0'; end if;
				if dot_count     = 010 then hsync_out <= '1';
					if line_count = 307 then vsync_out <= '1'; end if;
					if line_count = 311 then vsync_out <= '0'; end if;
				end if;

				if line_count = 298 then vblank <= '1'; end if;
				if line_count = 028 then vblank <= '0'; end if;

				if wide = '0' then
					if dot_count  = 490 then hblank <= '1'; end if;
					if dot_count  = 106 then hblank <= '0'; end if;
				else
					if dot_count  = 463 then hblank <= '1'; end if;
					if dot_count  = 133 then hblank <= '0'; end if;
				end if;
			end if;

		end if;
	end if;
end process;

end architecture;