-------------------------------------------------------------------------------
--
-- (C) COPYRIGHT 2010 Gideon's Logic Architectures'
--
-------------------------------------------------------------------------------
-- 
-- Author: Gideon Zweijtzer (gideon.zweijtzer (at) gmail.com)
--
-- Note that this file is copyrighted, and is not supposed to be used in other
-- projects without written permission from the author.
--
-- New mixer, updated noise generator // Alexey Melnikov
--
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity wave_map is
port
(
	clock    : in  std_logic;
	reset    : in  std_logic;

	osc_val  : in  unsigned(23 downto 0);
	carry_20 : in  std_logic;

	msb_other: in  std_logic := '0';
	ring_mod : in  std_logic := '0';
	test     : in  std_logic := '0';

	voice_i  : in  unsigned(1 downto 0);
	enable_i : in  std_logic;
	wave_sel : in  unsigned(3 downto 0);
	sq_width : in  unsigned(11 downto 0);

	voice_o  : out unsigned(1 downto 0);
	enable_o : out std_logic;
	wave_out : out unsigned(11 downto 0)
);
end wave_map;

architecture Gideon of wave_map is
	type noise_array_t is array (natural range <>) of unsigned(22 downto 0);
	signal noise_reg : noise_array_t(0 to 2) := (others => (others => '1'));

	signal triangle  : unsigned(11 downto 0);
	signal sawtooth  : unsigned(11 downto 0);
	signal pulse     : unsigned(11 downto 0);
	signal ring_msb  : std_logic;

	signal triangle0 : unsigned(11 downto 0);
	signal sawtooth0 : unsigned(11 downto 0);
	signal pulse0    : unsigned(11 downto 0);
	signal triangle1 : unsigned(11 downto 0);
	signal sawtooth1 : unsigned(11 downto 0);
	signal pulse1    : unsigned(11 downto 0);
	signal wave_sel1 : unsigned(3 downto 0);
	signal voice_o1  : unsigned(1 downto 0);
	signal enable_o1 : std_logic;
	signal noise1    : unsigned(11 downto 0);

	signal st_out    : unsigned(7 downto 0);
	signal pt_out    : unsigned(7 downto 0);
	signal ps_out    : unsigned(7 downto 0);
	signal pst_out   : unsigned(7 downto 0);
begin

ring_msb  <= (osc_val(23) xor (ring_mod and not msb_other));
triangle0 <= osc_val(22 downto 11) when ring_msb ='0' else not osc_val(22 downto 11);
sawtooth0 <= osc_val(23 downto 12);
pulse0    <= (others => '0') when osc_val(23 downto 12) < sq_width and test = '0' else (others => '1');

mixed_waves : work.waves 
port map
(
	clock   => clock,
	st_in   => osc_val(23 downto 12),
	st_out  => st_out,
	pt_in   => ring_msb & osc_val(22 downto 12),
	pt_out  => pt_out,
	ps_in   => osc_val(23 downto 12),
	ps_out  => ps_out,
	pst_in  => osc_val(23 downto 12),
	pst_out => pst_out
);

process(clock)
	variable noise : unsigned(22 downto 0);
begin
	if rising_edge(clock) then

		noise := noise_reg(to_integer(voice_i));
		if reset='1' or test='1' then
			noise := (others => '1');
		elsif carry_20='1' then
			noise := noise(21 downto 0) & (noise(22) xor noise(17));
		end if;
		
		wave_sel1 <= wave_sel;
		noise1    <= noise(20)&noise(18)&noise(14)&noise(11)&noise(9)&noise(5)&noise(2)&noise(0) & x"0";
		triangle1 <= triangle0;
		sawtooth1 <= sawtooth0;
		pulse1    <= pulse0;

		if enable_i='1' then
			noise_reg(to_integer(voice_i)) <= noise;
		end if;

		if reset='1' then
			noise_reg <= (others => (others => '1'));
		end if;

		voice_o1  <= voice_i;
		enable_o1 <= enable_i;
	end if;
end process;

process(clock)
	variable wave  : unsigned(11 downto 0);
begin
	if rising_edge(clock) then

		wave := (others => '0');
		if enable_o1 = '1' then
			case wave_sel1(2 downto 0) is
				when "000" => wave := (others => '0');
				when "001" => wave := triangle1;
				when "010" => wave := sawtooth1;
				when "011" => wave := st_out & x"0";
				when "100" => wave := pulse1;
				when "101" => wave := (pt_out & x"0")  and pulse1;
				when "110" => wave := (ps_out & x"0")  and pulse1;
				when "111" => wave := (pst_out & x"0") and pulse1;
			end case;
			if wave_sel1(3) = '1' then
				if wave_sel1(2 downto 0) = "000" then wave := x"fff"; end if;
				wave := wave and noise1;
			end if;
		end if;

		wave_out <= wave;
		voice_o  <= voice_o1;
		enable_o <= enable_o1;
	end if;
end process;

end Gideon;
