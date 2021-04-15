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

entity sid_top is
port (
    clock         : in  std_logic;
    reset         : in  std_logic;
                  
    addr          : in  std_logic_vector(4 downto 0);
    wren          : in  std_logic;
    wdata         : in  std_logic_vector(7 downto 0);
    rdata         : out std_logic_vector(7 downto 0);

    potx          : in  std_logic_vector(7 downto 0) := (others => '0');
    poty          : in  std_logic_vector(7 downto 0) := (others => '0');
	 
	 cfg           : in  std_logic_vector(2 downto 0);

    start_iter    : in  std_logic;
    sample        : out signed(17 downto 0);
	 
	 extfilter_en  : in  std_logic;

	 ld_clk        : in  std_logic;
	 ld_addr       : in  std_logic_vector(11 downto 0);
	 ld_data       : in  std_logic_vector(15 downto 0);
	 ld_wr         : in  std_logic
);
end sid_top;


architecture structural of sid_top is

    -- Voice index in pipe
    signal voice_osc   : unsigned(1 downto 0);
    signal voice_wave  : unsigned(1 downto 0);
    signal voice_mul   : unsigned(1 downto 0);
    signal enable_osc  : std_logic;
    signal enable_wave : std_logic;
    signal enable_mul  : std_logic;
    
    -- Oscillator parameters
    signal freq        : unsigned(15 downto 0);
    signal test        : std_logic;
    signal sync        : std_logic;

    -- Wave map parameters
    signal msb_other   : std_logic;
    signal ring_mod    : std_logic;
    signal wave_sel    : unsigned(3 downto 0);
    signal sq_width    : unsigned(11 downto 0);
    
    -- ADSR parameters
    signal gate        : std_logic;
    signal attack      : unsigned(3 downto 0);
    signal decay       : unsigned(3 downto 0);
    signal sustain     : unsigned(3 downto 0);
    signal release     : unsigned(3 downto 0);

    -- Filter enable
    signal filter_en   : std_logic;

    -- globals
    signal volume      : unsigned(3 downto 0);
    signal filter_co   : unsigned(10 downto 0);
    signal filter_res  : unsigned(3 downto 0);
    signal filter_hp   : std_logic;    
    signal filter_bp   : std_logic;
    signal filter_lp   : std_logic;
    signal voice3_off  : std_logic;

    -- readback
    signal osc3        : unsigned(7 downto 0);
    signal env3        : unsigned(7 downto 0);

    -- intermediate flags and signals
    signal test_wave   : std_logic;
    signal osc_val     : unsigned(23 downto 0);
    signal carry_20    : std_logic;
    signal enveloppe   : unsigned(7 downto 0);
    signal waveform    : unsigned(11 downto 0);

    signal valid_sum   : std_logic;
    signal valid_filt  : std_logic;
    signal valid_mix   : std_logic;

    signal filter_out  : signed(17 downto 0) := (others => '0');
    signal direct_out  : signed(17 downto 0) := (others => '0');
    signal high_pass   : signed(17 downto 0) := (others => '0');
    signal band_pass   : signed(17 downto 0) := (others => '0');
    signal low_pass    : signed(17 downto 0) := (others => '0');
    signal mixed_out   : signed(17 downto 0) := (others => '0');
	 
    signal dac_mode    : std_logic;
    signal dac_out     : signed(17 downto 0);

begin
 
	i_regs: entity work.sid_regs
	port map
	(
		clock       => clock,
		reset       => reset,

		addr        => addr,
		wren        => wren,
		wdata       => wdata,
		rdata       => rdata,
		
		potx        => potx,
		poty        => poty,

		voice_osc   => voice_osc,
		voice_wave  => voice_wave,
		voice_adsr  => voice_wave,
		voice_mul   => voice_mul,

		-- Oscillator parameters
		freq        => freq,
		test        => test,
		sync        => sync,

		-- Wave map parameters
		ring_mod    => ring_mod,
		wave_sel    => wave_sel,
		sq_width    => sq_width,

		-- ADSR parameters
		gate        => gate,
		attack      => attack,
		decay       => decay,
		sustain     => sustain,
		release     => release,

		-- mixer parameters
		filter_en   => filter_en,

		-- globals
		volume      => volume,
		filter_co   => filter_co,
		filter_res  => filter_res,
		filter_ex   => open,
		filter_hp   => filter_hp,    
		filter_bp   => filter_bp,
		filter_lp   => filter_lp,
		voice3_off  => voice3_off,

		dac_mode    => dac_mode,
		dac_out     => dac_out,

		-- readback
		osc3        => osc3,
		env3        => env3
	);

	i_ctrl: entity work.sid_ctrl
	port map
	(
		clock       => clock,
		reset       => reset,
		start_iter  => start_iter,
		voice_osc   => voice_osc,
		enable_osc  => enable_osc
	);
    
	osc: entity work.oscillator
	port map
	(
		clock     => clock,
		reset     => reset,

		voice_i   => voice_osc,
		voice_o   => voice_wave,

		enable_i  => enable_osc,
		enable_o  => enable_wave,

		freq      => freq,
		test      => test,
		sync      => sync,

		osc_val   => osc_val,
		test_o    => test_wave,
		carry_20  => carry_20,
		msb_other => msb_other
	);
    
	wmap: entity work.wave_map
	port map
	(
		clock     => clock,
		reset     => reset,
		test      => test_wave,
        
		osc_val   => osc_val,
		carry_20  => carry_20,
		msb_other => msb_other,
        
		voice_i   => voice_wave,
		enable_i  => enable_wave,
		wave_sel  => wave_sel,
		ring_mod  => ring_mod,
		sq_width  => sq_width,
    
		voice_o   => voice_mul,
		enable_o  => enable_mul,
		wave_out  => waveform
	);

	adsr: entity work.adsr_multi(sorg)
	port map
	(
		clock     => clock,
		reset     => reset,

		voice_i   => voice_wave,
		enable_i  => enable_wave,

		gate      => gate,
		attack    => attack,
		decay     => decay,
		sustain   => sustain,
		release   => release,

		env_out   => enveloppe
	);

	sum: entity work.mult_acc
	port map
	(
		clock      => clock,
		reset      => reset,

		voice_i    => voice_mul,
		enable_i   => enable_mul,
		voice3_off => voice3_off,

		enveloppe  => enveloppe,
		waveform   => waveform,
		filter_en  => filter_en,

		osc3       => osc3,
		env3       => env3,

		valid_out  => valid_sum,
		filter_out => filter_out,
		direct_out => direct_out
	);

	i_filt: entity work.sid_filter
	port map
	(
		clock       => clock,
		reset       => reset,
		enable      => extfilter_en,
		cfg         => unsigned(cfg),

		filt_co     => filter_co,
		filt_res    => filter_res,

		valid_in    => valid_sum,

		input       => filter_out,
		high_pass   => high_pass,
		band_pass   => band_pass,
		low_pass    => low_pass,

		valid_out   => valid_filt,

		ld_clk      => ld_clk,
		ld_addr     => ld_addr,
		ld_data     => ld_data,
		ld_wr       => ld_wr
	);

	mix: entity work.sid_mixer
	port map
	(
		clock       => clock,
		reset       => reset,

		valid_in    => valid_filt,

		direct_out  => direct_out,
		high_pass   => high_pass,
		band_pass   => band_pass,
		low_pass    => low_pass,

		filter_hp   => filter_hp,
		filter_bp   => filter_bp,
		filter_lp   => filter_lp,

		volume      => volume,

		mixed_out   => mixed_out
	);
	
	sample <= dac_out when dac_mode = '1' else mixed_out;

end structural;
