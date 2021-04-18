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
                  
    addr          : in  std_logic_vector(4 downto 0);
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
    wave_sel      : out unsigned(3 downto 0);
    sq_width      : out unsigned(11 downto 0);
    
    -- ADSR parameters
    gate          : out std_logic;
    attack        : out unsigned(3 downto 0);
    decay         : out unsigned(3 downto 0);
    sustain       : out unsigned(3 downto 0);
    release       : out unsigned(3 downto 0);

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
	 
    dac_mode      : out std_logic;
    dac_out       : out signed(17 downto 0);

    -- readback
    waveform      : in  unsigned(7 downto 0);
    enveloppe     : in  unsigned(7 downto 0)
);
end sid_regs;

architecture gideon of sid_regs is
	type byte_array_t is array(natural range <>) of std_logic_vector(7 downto 0);

	signal freq_lo   : byte_array_t(0 to 2) := (others => (others => '0'));
	signal freq_hi   : byte_array_t(0 to 2) := (others => (others => '0'));
	signal phase_lo  : byte_array_t(0 to 2) := (others => (others => '0'));
	signal phase_hi  : byte_array_t(0 to 2) := (others => (others => '0'));
	signal control   : byte_array_t(0 to 2) := (others => (others => '0'));
	signal att_dec   : byte_array_t(0 to 2) := (others => (others => '0'));
	signal sust_rel  : byte_array_t(0 to 2) := (others => (others => '0'));

	signal filt_en_i : std_logic_vector(2 downto 0) := (others => '0');
	signal last_wr   : std_logic_vector(7 downto 0);
	signal osc3      : std_logic_vector(7 downto 0);
	signal env3      : std_logic_vector(7 downto 0);

	type signed_array_t is array(natural range <>) of signed(17 downto 0);
	constant dac_map : signed_array_t(0 to 255) :=
	(
		-- 6581
		"00"&x"000B", "00"&x"2828", "00"&x"4FFA", "00"&x"7648", "00"&x"9D89", "00"&x"C1D2", "00"&x"E5BB", "01"&x"07FC",
		"01"&x"34E4", "01"&x"54A1", "01"&x"73EB", "01"&x"9197", "01"&x"AFCC", "01"&x"CB5A", "01"&x"E67A", "01"&x"FFFF",
		"11"&x"FDDD", "11"&x"F36E", "11"&x"E932", "11"&x"DFB6", "11"&x"D643", "11"&x"CD8F", "11"&x"C4FC", "11"&x"BCF3",
		"11"&x"B262", "11"&x"AB00", "11"&x"A3C0", "11"&x"9CF2", "11"&x"9613", "11"&x"8FAC", "11"&x"8960", "11"&x"8362",
		"11"&x"FFF8", "00"&x"27FE", "00"&x"4FBD", "00"&x"75E7", "00"&x"9CF6", "00"&x"C113", "00"&x"E4C0", "01"&x"06C6",
		"01"&x"3359", "01"&x"52DE", "01"&x"71E7", "01"&x"8F53", "01"&x"AD51", "01"&x"C89B", "01"&x"E374", "01"&x"FCC1",
		"11"&x"FE03", "11"&x"F88C", "11"&x"F32B", "11"&x"EE33", "11"&x"E951", "11"&x"E4BF", "11"&x"E03A", "11"&x"DC09",
		"11"&x"D678", "11"&x"D297", "11"&x"CEC4", "11"&x"CB36", "11"&x"C7AD", "11"&x"C452", "11"&x"C106", "11"&x"BDEA",
		"11"&x"FFB2", "00"&x"200D", "00"&x"4009", "00"&x"5EAB", "00"&x"7DFC", "00"&x"9ACF", "00"&x"B736", "00"&x"D249",
		"00"&x"F5C2", "01"&x"0ECA", "01"&x"2763", "01"&x"3EBB", "01"&x"5696", "01"&x"6C42", "01"&x"8195", "01"&x"95D0",
		"11"&x"FDC3", "11"&x"F32F", "11"&x"E8D8", "11"&x"DF41", "11"&x"D5BD", "11"&x"CCF3", "11"&x"C457", "11"&x"BC4D",
		"11"&x"B1A5", "11"&x"AA4B", "11"&x"A307", "11"&x"9C33", "11"&x"9561", "11"&x"8F01", "11"&x"88B3", "11"&x"82CB",
		"11"&x"FFA1", "00"&x"20CF", "00"&x"4195", "00"&x"60F6", "00"&x"8100", "00"&x"9E77", "00"&x"BB7A", "00"&x"D726",
		"00"&x"FB4A", "01"&x"14CC", "01"&x"2DE0", "01"&x"45A1", "01"&x"5DDD", "01"&x"73F1", "01"&x"8993", "01"&x"9E1A",
		"11"&x"FDE3", "11"&x"F7B9", "11"&x"F1AB", "11"&x"EC17", "11"&x"E69A", "11"&x"E17A", "11"&x"DC6B", "11"&x"D7BC",
		"11"&x"D180", "11"&x"CD2E", "11"&x"C8F2", "11"&x"C4F9", "11"&x"C108", "11"&x"BD54", "11"&x"B9A5", "11"&x"B632",
		"11"&x"FE60", "11"&x"FEE6", "11"&x"FF57", "11"&x"FFD5", "00"&x"0067", "00"&x"00D9", "00"&x"013C", "00"&x"01A9",
		"00"&x"0256", "00"&x"02A9", "00"&x"0308", "00"&x"0360", "00"&x"03D0", "00"&x"0421", "00"&x"046E", "00"&x"04B7",
		"11"&x"FBE3", "11"&x"D49F", "11"&x"AEF1", "11"&x"8BF8", "11"&x"6914", "11"&x"498B", "11"&x"2AE9", "11"&x"0E27",
		"10"&x"E7E7", "10"&x"CDCC", "10"&x"B44C", "10"&x"9C2E", "10"&x"83BF", "10"&x"6D5D", "10"&x"5768", "10"&x"4295",
		"11"&x"FE79", "00"&x"03FC", "00"&x"0956", "00"&x"0E78", "00"&x"13C5", "00"&x"1887", "00"&x"1D33", "00"&x"21A9",
		"00"&x"2794", "00"&x"2BAB", "00"&x"2FB7", "00"&x"3393", "00"&x"3798", "00"&x"3B27", "00"&x"3EC1", "00"&x"421D",
		"11"&x"FC68", "11"&x"DD67", "11"&x"BF8F", "11"&x"A3D3", "11"&x"8836", "11"&x"6F23", "11"&x"56BE", "11"&x"3FDE",
		"11"&x"2190", "11"&x"0CC7", "10"&x"F86C", "10"&x"E530", "10"&x"D1BF", "10"&x"BFD2", "10"&x"AE3A", "10"&x"9D8A",
		"11"&x"FE21", "11"&x"FC56", "11"&x"FA82", "11"&x"F8DF", "11"&x"F759", "11"&x"F5D7", "11"&x"F45C", "11"&x"F306",
		"11"&x"F143", "11"&x"F00A", "11"&x"EECD", "11"&x"EDAC", "11"&x"ECA7", "11"&x"EB92", "11"&x"EA8A", "11"&x"E996",
		"11"&x"FC1A", "11"&x"D8FC", "11"&x"B73E", "11"&x"97EA", "11"&x"78B9", "11"&x"5C75", "11"&x"40FE", "11"&x"273C",
		"11"&x"050C", "10"&x"EDAB", "10"&x"D6CD", "10"&x"C12F", "10"&x"AB52", "10"&x"973B", "10"&x"837C", "10"&x"70CB",
		"11"&x"FE3D", "00"&x"011C", "00"&x"03D7", "00"&x"0683", "00"&x"0951", "00"&x"0BCC", "00"&x"0E2F", "00"&x"1088",
		"00"&x"1390", "00"&x"15B5", "00"&x"17C7", "00"&x"19CF", "00"&x"1BF4", "00"&x"1DD8", "00"&x"1FAB", "00"&x"217E",
		"11"&x"FC78", "11"&x"E003", "11"&x"C49E", "11"&x"AB2C", "11"&x"91D4", "11"&x"7AD1", "11"&x"6469", "11"&x"4F6B",
		"11"&x"33A2", "11"&x"208F", "11"&x"0DE8", "10"&x"FC42", "10"&x"EA6F", "10"&x"DA07", "10"&x"C9DC", "10"&x"BAB9"

		-- 8580
--		"00"&x"97FB", "00"&x"AF31", "00"&x"C6B6", "00"&x"DDF3", "00"&x"F731", "01"&x"0EB0", "01"&x"25FB", "01"&x"3D20",
--		"01"&x"5A59", "01"&x"71EB", "01"&x"8906", "01"&x"A03C", "01"&x"B9F7", "01"&x"D0EA", "01"&x"E819", "01"&x"FFFF",
--		"00"&x"97D9", "00"&x"81F3", "00"&x"6C4D", "00"&x"56B8", "00"&x"3FE6", "00"&x"2A93", "00"&x"1543", "00"&x"003B",
--		"11"&x"E693", "11"&x"D17A", "11"&x"BCEB", "11"&x"A86C", "11"&x"9226", "11"&x"7DEE", "11"&x"69DB", "11"&x"55B9",
--		"00"&x"97FA", "00"&x"AEDA", "00"&x"C5E5", "00"&x"DCF8", "00"&x"F5C6", "01"&x"0CA7", "01"&x"23FA", "01"&x"3AB6",
--		"01"&x"575C", "01"&x"6E65", "01"&x"8585", "01"&x"9C42", "01"&x"B51A", "01"&x"CC62", "01"&x"E314", "01"&x"F9F9",
--		"00"&x"97C9", "00"&x"8202", "00"&x"6C74", "00"&x"56EF", "00"&x"4022", "00"&x"2AEE", "00"&x"15D6", "00"&x"00BD",
--		"11"&x"E721", "11"&x"D263", "11"&x"BD9B", "11"&x"A93B", "11"&x"9372", "11"&x"7EE1", "11"&x"6AE8", "11"&x"56F1",
--		"00"&x"97E2", "00"&x"AF9A", "00"&x"C749", "00"&x"DF06", "00"&x"F8BC", "01"&x"1042", "01"&x"2800", "01"&x"3FCE",
--		"01"&x"5D5B", "01"&x"74F6", "01"&x"8D10", "01"&x"A468", "01"&x"BDF7", "01"&x"D5CC", "01"&x"ED90", "01"&x"FFFF",
--		"00"&x"97BA", "00"&x"82B6", "00"&x"6DC7", "00"&x"5902", "00"&x"42DC", "00"&x"2E51", "00"&x"19DD", "00"&x"055F",
--		"11"&x"EC9D", "11"&x"D888", "11"&x"C46B", "11"&x"B077", "11"&x"9B78", "11"&x"87B3", "11"&x"73F8", "11"&x"60B3",
--		"00"&x"97D9", "00"&x"AF3F", "00"&x"C69E", "00"&x"DDF5", "00"&x"F741", "01"&x"0E94", "01"&x"25EF", "01"&x"3D60",
--		"01"&x"5AA2", "01"&x"71CC", "01"&x"893B", "01"&x"A0C8", "01"&x"B9C3", "01"&x"D121", "01"&x"E8DE", "01"&x"FFDB",
--		"00"&x"97AB", "00"&x"82C0", "00"&x"6DEC", "00"&x"5932", "00"&x"4322", "00"&x"2EA3", "00"&x"1A52", "00"&x"060C",
--		"11"&x"ED23", "11"&x"D935", "11"&x"C534", "11"&x"B14D", "11"&x"9C49", "11"&x"88C1", "11"&x"750E", "11"&x"61B2",
--		"00"&x"97DF", "00"&x"9793", "00"&x"9740", "00"&x"96DF", "00"&x"968A", "00"&x"9632", "00"&x"95D8", "00"&x"957E",
--		"00"&x"9525", "00"&x"94C0", "00"&x"945F", "00"&x"9419", "00"&x"93A8", "00"&x"934E", "00"&x"92FA", "00"&x"9288",
--		"00"&x"9790", "00"&x"6A14", "00"&x"3CC6", "00"&x"100A", "11"&x"E032", "11"&x"B405", "11"&x"885D", "11"&x"5D07",
--		"11"&x"2757", "10"&x"FCD4", "10"&x"D29C", "10"&x"A876", "10"&x"7B8F", "10"&x"527E", "10"&x"293E", "10"&x"0001",
--		"00"&x"97C7", "00"&x"9753", "00"&x"96E5", "00"&x"965F", "00"&x"95DD", "00"&x"9577", "00"&x"94F6", "00"&x"9474",
--		"00"&x"93DF", "00"&x"9384", "00"&x"92F1", "00"&x"927E", "00"&x"9206", "00"&x"917C", "00"&x"910B", "00"&x"90A0",
--		"00"&x"9790", "00"&x"6A46", "00"&x"3D54", "00"&x"10CB", "11"&x"E148", "11"&x"B574", "11"&x"89BE", "11"&x"5EF6",
--		"11"&x"29A3", "10"&x"FF08", "10"&x"D553", "10"&x"AB97", "10"&x"7E8F", "10"&x"55E2", "10"&x"2D29", "10"&x"0452",
--		"00"&x"97DF", "00"&x"9805", "00"&x"9849", "00"&x"9885", "00"&x"98B3", "00"&x"98ED", "00"&x"9929", "00"&x"9949",
--		"00"&x"9997", "00"&x"99E1", "00"&x"9A03", "00"&x"9A2D", "00"&x"9A72", "00"&x"9AC1", "00"&x"9AC6", "00"&x"9B09",
--		"00"&x"9799", "00"&x"6AEC", "00"&x"3EA1", "00"&x"12B4", "11"&x"E3E7", "11"&x"B8BA", "11"&x"8DB3", "11"&x"635A",
--		"11"&x"2EFE", "11"&x"050A", "10"&x"DB28", "10"&x"B2A4", "10"&x"865E", "10"&x"5D75", "10"&x"35E2", "10"&x"0DD3",
--		"00"&x"97BE", "00"&x"97D3", "00"&x"97F0", "00"&x"9812", "00"&x"982E", "00"&x"982D", "00"&x"984A", "00"&x"9873",
--		"00"&x"986E", "00"&x"988B", "00"&x"98B0", "00"&x"98B1", "00"&x"98BF", "00"&x"98F3", "00"&x"98EF", "00"&x"9907",
--		"00"&x"9785", "00"&x"6B39", "00"&x"3F2F", "00"&x"139A", "11"&x"E4D0", "11"&x"BA24", "11"&x"8F75", "11"&x"6513",
--		"11"&x"3140", "11"&x"07A4", "10"&x"DE0F", "10"&x"B4E5", "10"&x"89E2", "10"&x"6143", "10"&x"38B8", "10"&x"11F6"
	);

begin
	process(clock)
	begin
		if rising_edge(clock) then
			if wren='1' then
				last_wr <= wdata;
				case addr is
					when "00000" => freq_lo (0) <= wdata;
					when "00001" => freq_hi (0) <= wdata;
					when "00010" => phase_lo(0) <= wdata;
					when "00011" => phase_hi(0) <= wdata;
					when "00100" => control (0) <= wdata;
					when "00101" => att_dec (0) <= wdata;
					when "00110" => sust_rel(0) <= wdata;
					when "00111" => freq_lo (1) <= wdata;
					when "01000" => freq_hi (1) <= wdata;
					when "01001" => phase_lo(1) <= wdata;
					when "01010" => phase_hi(1) <= wdata;
					when "01011" => control (1) <= wdata;
					when "01100" => att_dec (1) <= wdata;
					when "01101" => sust_rel(1) <= wdata;
					when "01110" => freq_lo (2) <= wdata;
					when "01111" => freq_hi (2) <= wdata;
					when "10000" => phase_lo(2) <= wdata;
					when "10001" => phase_hi(2) <= wdata;
					when "10010" => control (2) <= wdata;
					when "10011" => att_dec (2) <= wdata;
					when "10100" => sust_rel(2) <= wdata;
					when "10101" => filter_co( 2 downto 0) <= unsigned(wdata(2 downto 0));
					when "10110" => filter_co(10 downto 3) <= unsigned(wdata);
					when "10111" => filter_res  <= unsigned(wdata(7 downto 4));
										 filter_ex   <= wdata(3);
										 filt_en_i   <= wdata(2 downto 0);
					when "11000" => voice3_off  <= wdata(7);
										 filter_hp   <= wdata(6);
										 filter_bp   <= wdata(5);
										 filter_lp   <= wdata(4);
										 volume      <= unsigned(wdata(3 downto 0));
										 dac_out     <= dac_map(to_integer(unsigned(wdata)));
					when others => null;
				end case;
			end if;

			-- Read
			case addr is
				when "11001" => rdata <= potx;
				when "11010" => rdata <= poty;
				when "11011" => rdata <= osc3;
				when "11100" => rdata <= env3;
				when others  => rdata <= last_wr;
			end case;

			-- hack for 8-bit DAC mode
			if (control(0) and x"F9") = X"49" and (control(1) and x"F9") = X"49" and (control(2) and x"F9") = X"49" then
				dac_mode <= '1';
			else
				dac_mode <= '0';
			end if;

			if reset='1' then
				freq_lo    <= (others => (others => '0'));
				freq_hi    <= (others => (others => '0'));
				phase_lo   <= (others => (others => '0'));
				phase_hi   <= (others => (others => '0'));
				control    <= (others => (others => '0'));
				att_dec    <= (others => (others => '0'));
				sust_rel   <= (others => (others => '0'));
				filter_res <= (others => '0');
				filter_ex  <= '0';
				filt_en_i  <= (others => '0');
				filter_co  <= (others => '0');
				filter_hp  <= '0';
				filter_bp  <= '0';
				filter_lp  <= '0';
				volume     <= (others => '0');
				voice3_off <= '0';
				dac_out    <= (others => '0');
			end if;
		end if;
	end process;

	freq      <= unsigned(freq_hi(to_integer(voice_osc))) & unsigned(freq_lo(to_integer(voice_osc)));
	test      <= control(to_integer(voice_osc))(3);
	sync      <= control(to_integer(voice_osc))(1);

	-- Wave map parameters
	ring_mod  <= control(to_integer(voice_wave))(2);
	wave_sel  <= unsigned(control(to_integer(voice_wave))(7 downto 4));
	sq_width  <= unsigned(phase_hi(to_integer(voice_wave))(3 downto 0)) & unsigned(phase_lo(to_integer(voice_wave)));

	-- ADSR parameters
	gate      <= control(to_integer(voice_adsr))(0);
	attack    <= unsigned(att_dec(to_integer(voice_adsr))(7 downto 4));
	decay     <= unsigned(att_dec(to_integer(voice_adsr))(3 downto 0));
	sustain   <= unsigned(sust_rel(to_integer(voice_adsr))(7 downto 4));
	release   <= unsigned(sust_rel(to_integer(voice_adsr))(3 downto 0));

	-- Mixer 1 parameters
	filter_en <= filt_en_i(to_integer(voice_mul));

	process(clock)
	begin
		if rising_edge(clock) then
			if voice_mul = 2 then
				osc3 <= std_logic_vector(waveform);
				env3 <= std_logic_vector(enveloppe);
			end if;
		end if;
	end process;

end gideon;
