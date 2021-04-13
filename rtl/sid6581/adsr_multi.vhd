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

-- LUT: 195, FF:68

entity adsr_multi is
port
(
	clock    : in  std_logic;
	reset    : in  std_logic;

	voice_i  : in  unsigned(1 downto 0);
	enable_i : in  std_logic;
	voice_o  : out unsigned(1 downto 0);
	enable_o : out std_logic;

	gate     : in  std_logic;
	attack   : in  std_logic_vector(3 downto 0);
	decay    : in  std_logic_vector(3 downto 0);
	sustain  : in  std_logic_vector(3 downto 0);
	release  : in  std_logic_vector(3 downto 0);

	env_out  : out unsigned(7 downto 0)
);
end adsr_multi;

-- 158 1   62 .. FF
-- 45  2   35 .. 61
-- 26  4   1C .. 34
-- 13  8   0D .. 1B
-- 6   16  07 .. 0C
-- 7   30  00 .. 06

architecture gideon of adsr_multi is
    type presc_array_t is array(natural range <>) of unsigned(15 downto 0);
    constant prescalers : presc_array_t(0 to 15) := (
        X"0008", X"001F", X"003E", X"005E",
        X"0094", X"00DB", X"010A", X"0138", 
        X"0187", X"03D0", X"07A1", X"0C35", 
        X"0F42", X"2DC7", X"4C4B", X"7A12" );


    signal enveloppe : unsigned(7 downto 0)  := (others => '0');
    signal state     : unsigned(1 downto 0)  := (others => '0');
    
    constant st_release : unsigned(1 downto 0) := "00";
    constant st_attack  : unsigned(1 downto 0) := "01";
    constant st_decay   : unsigned(1 downto 0) := "11";
    
    type state_array_t is array(natural range <>) of unsigned(29 downto 0);
    signal state_array : state_array_t(0 to 2) := (others => (others => '0'));
begin
    env_out   <= enveloppe;

    -- FF-5E 01
    -- 5D-37 02
    -- 36-1B 04
    -- 1A-0F 08
    -- 0E-07 10
    -- 06-01 1E
    process(clock)
        function logarithmic(lev: unsigned(7 downto 0)) return unsigned is
            variable res : unsigned(4 downto 0);
        begin
            if lev = X"00" then
                res := "00000"; -- prescaler off
            elsif lev < X"07" then
                res := "11101"; -- 1E-1
            elsif lev < X"0F" then
                res := "01111"; -- 10-1
            elsif lev < X"1B" then
                res := "00111"; -- 08-1
            elsif lev < X"37" then
                res := "00011"; -- 04-1
            elsif lev < X"5E" then
                res := "00001"; -- 02-1
            else
                res := "00000"; -- 01-1
            end if;
            return res;
        end function logarithmic;

        variable presc_select : integer range 0 to 15;
        variable cur_state    : unsigned(1 downto 0);
        variable cur_env      : unsigned(7 downto 0);
        variable cur_pre15    : unsigned(14 downto 0);
        variable cur_pre5     : unsigned(4 downto 0);
        variable next_state   : unsigned(1 downto 0);
        variable next_env     : unsigned(7 downto 0);
        variable next_pre15   : unsigned(14 downto 0);
        variable next_pre5    : unsigned(4 downto 0);
        variable presc_val    : unsigned(14 downto 0);
        variable log_div      : unsigned(4 downto 0);
        variable do_count_15  : std_logic;
        variable do_count_5   : std_logic;
    begin
        if rising_edge(clock) then
            cur_state := state_array(to_integer(voice_i))(1 downto 0);
            cur_env   := state_array(to_integer(voice_i))(9 downto 2);
            cur_pre15 := state_array(to_integer(voice_i))(24 downto 10);
            cur_pre5  := state_array(to_integer(voice_i))(29 downto 25);

            voice_o  <= voice_i;
            enable_o <= enable_i;

            next_state := cur_state;
            next_env   := cur_env;
            next_pre15 := cur_pre15;
            next_pre5  := cur_pre5;


            -- PRESCALER LOGIC, output: do_count --
            -- 15 bit prescaler select --
            case cur_state is
            when st_attack =>
                presc_select := to_integer(unsigned(attack));
            when st_decay =>
                presc_select := to_integer(unsigned(decay));
            when others => -- includes release and idle
                presc_select := to_integer(unsigned(release));
            end case;
            presc_val := prescalers(presc_select)(14 downto 0);            
            
            -- 15 bit prescaler counter -- 
            do_count_15 := '0';
            if cur_pre15 = presc_val then
                next_pre15 := (others => '0');
                do_count_15 := '1';
            else
                next_pre15 := cur_pre15 + 1;
            end if;

            -- 5 bit prescaler --
            log_div := logarithmic(cur_env);
            do_count_5 := '0';
            if do_count_15='1' then
                if (cur_state = st_attack) or cur_pre5 = log_div then
                    next_pre5 := "00000";
                    do_count_5 := '1';
                else
                    next_pre5 := cur_pre5 + 1;
                end if;
            end if;
            -- END PRESCALER LOGIC --

            case cur_state is
            
            when st_attack =>
                if gate = '0' then
                    next_state := st_release;
                elsif cur_env = X"FF" then
                    next_state := st_decay;
                end if;
                
                if do_count_15='1' then
                    next_env := cur_env + 1;
--                    if cur_env = X"FE" or cur_env = X"FF" then -- result could be FF, but also 00!!
--                        next_state := st_decay;
--                    end if;
                end if;
            
            when st_decay =>
                if gate = '0' then
                    next_state := st_release;
                end if;
                
                if do_count_15='1' and do_count_5='1' and 
                    std_logic_vector(cur_env) /= (sustain & sustain) and
                    cur_env /= X"00" then
                    next_env := cur_env - 1;
                end if;

            when st_release =>
                if gate = '1' then
                    next_state := st_attack;
                end if;                    
            
                if do_count_15='1' and do_count_5='1' and 
                    cur_env /= X"00" then
                    next_env := cur_env - 1;
                end if;

            when others =>
                next_state := st_release;
                
            end case;

            if enable_i='1' then
                state_array(to_integer(voice_i)) <= next_pre5 & next_pre15 & next_env & next_state;
                enveloppe <= next_env;
                state <= next_state;
            end if;

            if reset='1' then
					 state_array <= (others => (others => '0'));
                state       <= "00";
                enveloppe   <= (others => '0');
                enable_o    <= '0';
            end if;
        end if;
    end process;
end gideon;

--
-- Another hopefully better implementation of Envelope (Alexey Melnikov)
--
architecture sorg of adsr_multi is
	constant ST_RELEASE : unsigned(1 downto 0) := "00";
	constant ST_ATTACK  : unsigned(1 downto 0) := "01";
	constant ST_DEC_SUS : unsigned(1 downto 0) := "11";

	type state_array_t is array(natural range <>) of unsigned(31 downto 0);
	signal state_array : state_array_t(0 to 2) := (others => (others => '0'));

	type presc_array_t is array(natural range <>) of unsigned(15 downto 0);
	constant adsrtable : presc_array_t(0 to 15) := (
		X"0008", X"001F", X"003E", X"005E",
		X"0094", X"00DB", X"010A", X"0138", 
		X"0187", X"03D0", X"07A1", X"0C35", 
		X"0F42", X"2DC7", X"4C4B", X"7A12" );
begin

	process (clock)
		variable pre15_max  : unsigned(14 downto 0);
		variable cur_pre15  : unsigned(14 downto 0);
		variable pre5_max   : unsigned(4 downto 0);
		variable cur_pre5   : unsigned(4 downto 0);
		variable gate_old   : std_logic;
		variable state      : unsigned(1 downto 0);
		variable count      : std_logic;
		variable env        : unsigned(7 downto 0);
	begin
		if rising_edge(clock) then
			state     := state_array(to_integer(voice_i))( 1 downto  0);
			env       := state_array(to_integer(voice_i))( 9 downto  2);
			cur_pre15 := state_array(to_integer(voice_i))(24 downto 10);
			cur_pre5  := state_array(to_integer(voice_i))(29 downto 25);
			gate_old  := state_array(to_integer(voice_i))(30);
			count     := state_array(to_integer(voice_i))(31);

			   if env > 93 then pre5_max := "00000";
			elsif env > 54 then pre5_max := "00001";
			elsif env > 26 then pre5_max := "00011";
			elsif env > 14 then pre5_max := "00111";
			elsif env > 6  then pre5_max := "01111";
			elsif env > 0  then pre5_max := "11101";
			else                pre5_max := "00000";
			end if;

			   if state = ST_ATTACK  then pre15_max := adsrtable(to_integer(unsigned(attack))) (14 downto 0);
			elsif state = ST_DEC_SUS then pre15_max := adsrtable(to_integer(unsigned(decay)))  (14 downto 0);
			else                          pre15_max := adsrtable(to_integer(unsigned(release)))(14 downto 0);
			end if;
			
			if cur_pre15 = pre15_max then
				cur_pre15 := (others => '0');
				
				if state = ST_ATTACK or cur_pre5 = pre5_max then
					cur_pre5 := (others => '0');
					
					case state is
						when ST_ATTACK =>
							if env = x"FE" then
								state := ST_DEC_SUS;
							end if;
							env := env + 1;

						when ST_DEC_SUS =>
							if env /= unsigned(sustain & sustain) and count = '1' then
								env := env - 1;
							end if;

						when ST_RELEASE =>
							if count = '1' then
								env := env - 1;
							end if;
						
						when others => null;
					end case;

					if state /= ST_ATTACK and env = 0 then
						count := '0';
					end if;
				else
					cur_pre5 := cur_pre5 + 1;
				end if;
			else
				cur_pre15 := cur_pre15 + 1;
			end if;
			
			if gate_old = '0' and gate = '1' then
				state := ST_ATTACK;
				count := '1';
			end if;
			if gate_old = '1' and gate = '0' then
				state := ST_RELEASE;
			end if;

			if enable_i='1' then
				 state_array(to_integer(voice_i)) <= count & gate & cur_pre5 & cur_pre15 & env & state;
				 env_out <= env;
			end if;

			voice_o  <= voice_i;
			enable_o <= enable_i;

			if reset='1' then
				 state_array <= (others => (others => '0'));
				 env_out     <= (others => '0');
				 enable_o    <= '0';
			end if;
		end if;
	end process;
end architecture;
