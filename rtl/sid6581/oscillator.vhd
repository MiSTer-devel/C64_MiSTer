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

entity oscillator is
port
(
	clock    : in  std_logic;
	reset    : in  std_logic;

	enable_i : in  std_logic;
	voice_i  : in  unsigned(1 downto 0);
	freq     : in  unsigned(15 downto 0);
	test     : in  std_logic := '0';
	sync     : in  std_logic := '0';

	voice_o  : out unsigned(1 downto 0);
	enable_o : out std_logic;
	test_o   : out std_logic;
	osc_val  : out unsigned(23 downto 0);
	carry_20 : out std_logic;
	msb_other: out std_logic
);
end oscillator;


architecture Gideon of oscillator is
    type accu_array_t is array (natural range <>) of unsigned(23 downto 0);
    signal accu_reg  : accu_array_t(0 to 2) := (others => (others => '0'));

    type int2_array is array (natural range <>) of integer range 0 to 2;
    constant linked_voice : int2_array(0 to 2) := (2,0,1);

    signal msb_register : std_logic_vector(0 to 2) := (others => '0');
    signal car_register : std_logic_vector(0 to 2) := (others => '0');
    signal do_sync      : std_logic;
begin
    do_sync <= sync and car_register(linked_voice(to_integer(voice_i)));
    
    process(clock)
        variable cur_accu   : unsigned(23 downto 0);
        variable new_accu   : unsigned(24 downto 0);
        variable cur_20     : std_logic;
    begin
        if rising_edge(clock) then
            cur_accu := accu_reg(to_integer(voice_i));
            cur_20   := cur_accu(20);

            if reset='1' or test='1' or do_sync='1' then
                new_accu := (others => '0');
            else
                new_accu := ('0' & cur_accu) + freq;
            end if;

            osc_val   <= new_accu(23 downto 0);
            carry_20  <= new_accu(20) xor cur_20;
            msb_other <= msb_register(linked_voice(to_integer(voice_i)));
            voice_o   <= voice_i;
            enable_o  <= enable_i;
            test_o    <= test;

            if enable_i='1' then
                accu_reg(to_integer(voice_i)) <= new_accu(23 downto 0);
                car_register(to_integer(voice_i)) <= new_accu(24);
                msb_register(to_integer(voice_i)) <= cur_accu(23);
            end if;

            if reset='1' then
					 accu_reg     <= (others => (others => '0'));
					 msb_register <= (others => '0');
					 car_register <= (others => '0');
            end if;
        end if;
    end process;

end Gideon;
