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

entity sid_regs is
port (
    clock         : in  std_logic;
    reset         : in  std_logic;
                  
    addr          : in  unsigned(4 downto 0);
    wren          : in  std_logic;
    wdata         : in  std_logic_vector(7 downto 0);
    rdata         : out std_logic_vector(7 downto 0);
    
    potx          : in  std_logic_vector(7 downto 0);
    poty          : in  std_logic_vector(7 downto 0);

    voice_osc     : in  unsigned(1 downto 0);
    voice_wave    : in  unsigned(1 downto 0);
    voice_adsr    : in  unsigned(1 downto 0);
    voice_mul     : in  unsigned(1 downto 0);
    
    -- Oscillator parameters
    freq          : out unsigned(15 downto 0);
    test          : out std_logic;
    sync          : out std_logic;
    
    -- Wave map parameters
    ring_mod      : out std_logic;
    wave_sel      : out std_logic_vector(3 downto 0);
    sq_width      : out unsigned(11 downto 0);
    
    -- ADSR parameters
    gate          : out std_logic;
    attack        : out std_logic_vector(3 downto 0);
    decay         : out std_logic_vector(3 downto 0);
    sustain       : out std_logic_vector(3 downto 0);
    release       : out std_logic_vector(3 downto 0);

    -- mixer 1 parameters
    filter_en     : out std_logic;

    -- globals
    volume        : out unsigned(3 downto 0)  := (others => '0');
    filter_co     : out unsigned(10 downto 0) := (others => '0');
    filter_res    : out unsigned(3 downto 0)  := (others => '0');
    filter_ex     : out std_logic := '0';
    filter_hp     : out std_logic := '0';    
    filter_bp     : out std_logic := '0';
    filter_lp     : out std_logic := '0';
    voice3_off    : out std_logic := '0';

    -- readback
    osc3        : in  std_logic_vector(7 downto 0);
    env3        : in  std_logic_vector(7 downto 0) );

	 attribute ramstyle : string;

end sid_regs;

architecture gideon of sid_regs is
	 attribute ramstyle of gideon : architecture is "logic";

    type byte_array_t is array(natural range <>) of std_logic_vector(7 downto 0);

    signal freq_lo  : byte_array_t(0 to 2)  := (others => (others => '0'));
    signal freq_hi  : byte_array_t(0 to 2)  := (others => (others => '0'));
    signal phase_lo : byte_array_t(0 to 2)  := (others => (others => '0'));
    signal phase_hi : byte_array_t(0 to 2)  := (others => (others => '0'));
    signal control  : byte_array_t(0 to 2)  := (others => (others => '0'));
    signal att_dec  : byte_array_t(0 to 2)  := (others => (others => '0'));
    signal sust_rel : byte_array_t(0 to 2)  := (others => (others => '0'));

    signal filt_en_i: std_logic_vector(2 downto 0) := (others => '0');
	 signal last_wr  : std_logic_vector(7 downto 0);
begin
	process(clock)
		variable voice : integer range 0 to 3; 
		variable reg   : unsigned(2 downto 0);
	begin
		if rising_edge(clock) then
			if wren='1' then
				last_wr <= wdata;
				if addr < "10101" then
					voice := 0;
					reg := addr(2 downto 0);
					if addr >= "01110" then
						voice := 2;
						reg := addr(2 downto 0) - "110";
					elsif addr >= "00111" then
						voice := 1;
						reg := addr(2 downto 0) - "111";
					end if;
					
					case reg is
						when  "000" => freq_lo (voice) <= wdata;
						when  "001" => freq_hi (voice) <= wdata;
						when  "010" => phase_lo(voice) <= wdata;
						when  "011" => phase_hi(voice) <= wdata;
						when  "100" => control (voice) <= wdata;
						when  "101" => att_dec (voice) <= wdata;
						when  "110" => sust_rel(voice) <= wdata;
						when others => null;
					end case;
				elsif addr = "10101" then filter_co(2 downto 0) <= unsigned(wdata(2 downto 0));
				elsif addr = "10110" then filter_co(10 downto 3) <= unsigned(wdata);
            elsif addr = "10111" then filter_res <= unsigned(wdata(7 downto 4));
												  filter_ex  <= wdata(3);
												  filt_en_i(2 downto 0) <= wdata(2 downto 0);
				elsif addr = "11000" then voice3_off <= wdata(7);
												  filter_hp  <= wdata(6);
												  filter_bp  <= wdata(5);
												  filter_lp  <= wdata(4);
												  volume     <= unsigned(wdata(3 downto 0));
				end if;
			end if;

			-- Read
			case addr is
			when "11001" => rdata <= potx;
			when "11010" => rdata <= poty;
			when "11011" => rdata <= osc3;
			when "11100" => rdata <= env3;
			when others  => rdata <= last_wr;
			end case;

			if reset='1' then
				 freq_lo  <= (others => (others => '0'));
				 freq_hi  <= (others => (others => '0'));
				 phase_lo <= (others => (others => '0'));
				 phase_hi <= (others => (others => '0'));
				 control  <= (others => (others => '0'));
				 att_dec  <= (others => (others => '0'));
				 sust_rel <= (others => (others => '0'));

				 filt_en_i  <= (others => '0');
				 volume     <=  (others => '0');
				 voice3_off <= '0';
			end if;
		end if;
	end process;

	freq      <= unsigned(freq_hi(to_integer(voice_osc))) & unsigned(freq_lo(to_integer(voice_osc)));
	test      <= control(to_integer(voice_osc))(3);
	sync      <= control(to_integer(voice_osc))(1);

	-- Wave map parameters
	ring_mod  <= control(to_integer(voice_wave))(2);
	wave_sel  <= control(to_integer(voice_wave))(7 downto 4);
	sq_width  <= unsigned(phase_hi(to_integer(voice_wave))(3 downto 0)) & unsigned(phase_lo(to_integer(voice_wave)));

	-- ADSR parameters
	gate      <= control(to_integer(voice_adsr))(0);
	attack    <= att_dec(to_integer(voice_adsr))(7 downto 4);
	decay     <= att_dec(to_integer(voice_adsr))(3 downto 0);
	sustain   <= sust_rel(to_integer(voice_adsr))(7 downto 4);
	release   <= sust_rel(to_integer(voice_adsr))(3 downto 0);

	-- Mixer 1 parameters
	filter_en <= filt_en_i(to_integer(voice_mul));
	  
end gideon;
