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
generic (
    g_num_voices  : integer := 8;  -- 8 or 16, clock should then be 8 or 16 MHz, too!
    g_sample_bits : integer := 8 );
port (
    clock    : in  std_logic;
    reset    : in  std_logic;
    
    osc_val  : in  unsigned(23 downto 0);
    carry_20 : in  std_logic;

    msb_other: in  std_logic := '0';
    ring_mod : in  std_logic := '0';
    test     : in  std_logic := '0';
       
    voice_i  : in  unsigned(3 downto 0);
    enable_i : in  std_logic;
    wave_sel : in  std_logic_vector(3 downto 0);
    sq_width : in  unsigned(11 downto 0);

    voice_o  : out unsigned(3 downto 0);
    enable_o : out std_logic;
    wave_out : out unsigned(g_sample_bits-1 downto 0) );

end wave_map;


architecture Gideon of wave_map is
	type noise_array_t is array (natural range <>) of unsigned(22 downto 0);
	signal noise_reg : noise_array_t(0 to g_num_voices-1) := (others => (others => '1'));

	signal triangle : unsigned(11 downto 0);
	signal sawtooth : unsigned(11 downto 0);
	signal pulse    : unsigned(11 downto 0);
begin

triangle <= osc_val(22 downto 11) when (osc_val(23) xor (ring_mod and not msb_other)) ='0' else not osc_val(22 downto 11);
sawtooth <= osc_val(23 downto 12);
pulse    <= (others => '0')       when osc_val(23 downto 12) < sq_width                    else (others => '1');

process(clock)
	variable noise : unsigned(22 downto 0);
	variable wave  : unsigned(11 downto 0);
begin
	if rising_edge(clock) then

		noise := noise_reg(to_integer(voice_i));
		if reset='1' or test='1' then
			noise := (others => '1');
		elsif carry_20='1' then
			noise := noise(21 downto 0) & (noise(22) xor noise(17));
		end if;
		
		wave := (others => '0');
		if wave_sel  /= x"0" then wave := (others => '1');   end if; 
		if wave_sel(0) = '1' then wave := wave and triangle; end if;
		if wave_sel(1) = '1' then wave := wave and sawtooth; end if;
		if wave_sel(2) = '1' then wave := wave and pulse;    end if;
		if wave_sel(3) = '1' then wave := wave and (noise(20)&noise(18)&noise(14)&noise(11)&noise(9)&noise(5)&noise(2)&noise(0) & x"0"); end if;

		if enable_i='1' then
			noise_reg(to_integer(voice_i)) <= noise;
		end if;

		wave_out <= wave(11 downto 12-g_sample_bits);
		voice_o  <= voice_i;
		enable_o <= enable_i;
  end if;
end process;

end Gideon;
