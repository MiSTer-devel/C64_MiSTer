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
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.my_math_pkg.all;

entity mult_acc is
port (
	clock           : in  std_logic;
	reset           : in  std_logic;

	voice_i         : in  unsigned(1 downto 0);
	enable_i        : in  std_logic;
	voice3_off      : in  std_logic;

	filter_en       : in  std_logic := '0';

	enveloppe       : in  unsigned(7 downto 0);
	waveform        : in  unsigned(11 downto 0);

	--
	valid_out       : out std_logic;

	direct_out      : out signed(17 downto 0);
	filter_out      : out signed(17 downto 0)
);
end mult_acc;

architecture signed_wave of mult_acc is
    signal filter_m : std_logic;
    signal voice_m  : unsigned(1 downto 0);
    signal mult_m   : signed(20 downto 0);
    signal accu_f   : signed(17 downto 0);
    signal accu_u   : signed(17 downto 0);
    signal enable_d : std_logic;
begin
    process(clock)
        variable mult_ext   : signed(21 downto 0);
        variable mult_trunc : signed(21 downto 4);
    begin
        if rising_edge(clock) then

            mult_ext   := mult_m(mult_m'length-1) & mult_m;
            mult_trunc := mult_ext(mult_trunc'range);
            filter_m   <= filter_en;
            voice_m    <= voice_i;
            mult_m     <= signed('0' & enveloppe) * signed(not waveform(11) & waveform(10 downto 0)); 
            valid_out  <= '0';
            enable_d   <= enable_i;

            if enable_d='1' then
                if voice_m = 0 then
                    valid_out <= '1';
                    direct_out <= accu_u;
                    filter_out <= accu_f;
                    if filter_m='1' then
                        accu_f <= mult_trunc;
                        accu_u <= (others => '0');
                    else
                        accu_f <= (others => '0');
                        accu_u <= mult_trunc;
                    end if;
                else
                    if filter_m='1' then
                        accu_f <= sum_limit(accu_f, mult_trunc);
                    elsif (voice_m /= 2) or (voice3_off = '0') then
                        accu_u <= sum_limit(accu_u, mult_trunc);
                    end if;
                end if;
            end if;

            if reset = '1' then
                valid_out  <= '0';
                accu_u     <= (others => '0');
                accu_f     <= (others => '0');
                direct_out <= (others => '0');
                filter_out <= (others => '0');
            end if;
        end if;
    end process;

end signed_wave;
