---------------------------------------------------------------------------------
-- Commodore 1541 gcr floppy (read only) by Dar (darfpga@aol.fr) 02-April-2015
-- http://darfpga.blogspot.fr
--
-- produces GCR data, byte(ready) and sync signal to feed c1541_logic from current
-- track buffer ram which contains D64 data
--
-- Input clk 32MHz
--
---------------------------------------------------------------------------------
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.std_logic_unsigned.ALL;
use IEEE.numeric_std.all;

entity gcr_floppy is
port(
	clk32       : in  std_logic;
	reset       : in  std_logic;

	do          : out std_logic_vector(7 downto 0);   -- disk read data
	stp         : in  std_logic_vector(1 downto 0);   -- stepper motor control
	mtr         : in  std_logic;                      -- stepper motor on/off
	sync_n      : out std_logic;                      -- reading SYNC bytes
	byte_n      : out std_logic;                      -- byte ready

	track       : out std_logic_vector(5 downto 0);
	sector      : out std_logic_vector(4 downto 0);
	byte_addr   : out std_logic_vector(7 downto 0);
	track_din   : in  std_logic_vector(7 downto 0);
	track_ready : in  std_logic
);
end gcr_floppy;

architecture struct of gcr_floppy is

	signal bit_clk_en  : std_logic;
	signal sync_cnt    : std_logic_vector(5 downto 0) := (others => '0');
	signal byte_cnt    : std_logic_vector(8 downto 0) := (others => '0');
	signal byte_dbl    : std_logic_vector(7 downto 0) := (others => '0');
	signal nibble      : std_logic := '0';
	signal gcr_bit_cnt : std_logic_vector(3 downto 0) := (others => '0');
	signal bit_cnt     : std_logic_vector(2 downto 0) := (others => '0');

	signal sync_in_n   : std_logic;
	signal byte_in_n   : std_logic;

	signal sector_dbl  : std_logic_vector(4 downto 0) := (others => '0');
	signal state       : std_logic                    := '0';

	signal data_header : std_logic_vector(7 downto 0);
	signal data_body   : std_logic_vector(7 downto 0);
	signal data        : std_logic_vector(7 downto 0);
	signal data_cks    : std_logic_vector(7 downto 0);
	signal gcr_nibble  : std_logic_vector(4 downto 0);
	signal gcr_bit     : std_logic;
	signal gcr_byte    : std_logic_vector(7 downto 0);
	signal track_dbl   : std_logic_vector(6 downto 0);
	signal stp_r       : std_logic_vector(1 downto 0);

	type gcr_array is array(0 to 15) of std_logic_vector(4 downto 0);

	signal gcr_lut : gcr_array := 
		("01010","11010","01001","11001","01110","11110","01101","11101",
		 "10010","10011","01011","11011","10110","10111","01111","10101");

	signal sector_max : std_logic_vector(4 downto 0);

begin

	track <= track_dbl(6 downto 1);
	sector <= sector_dbl;

	process(clk32)
	begin
		if rising_edge(clk32) then
			stp_r <= stp;
			if reset = '1' then
				track_dbl <= "0000010";
			else
				if mtr = '1' then
					if((stp_r = "00" and stp = "10")
					or (stp_r = "10" and stp = "01")
					or (stp_r = "01" and stp = "11")
					or (stp_r = "11" and stp = "00")) then
						if track_dbl < "1010000" then
							track_dbl <= std_logic_vector(unsigned(track_dbl) + 1);
						end if;
					end if;
				
					if((stp_r = "00" and stp = "11")
					or (stp_r = "10" and stp = "00")
					or (stp_r = "01" and stp = "10")
					or (stp_r = "11" and stp = "01")) then 
						if track_dbl > "0000001" then
							track_dbl <= std_logic_vector(unsigned(track_dbl) - 1);
						end if;
					end if;
				end if;
			end if;
		end if;
	end process;

	sync_n <= sync_in_n when mtr = '1' and track_ready = '1' else '1';

	with byte_cnt select
		data_header <= 
			X"08"                       when "000000000",
			"00"&track_dbl(6 downto 1) xor "000"&sector_dbl when "000000001",
			"000"&sector_dbl            when "000000010",
			"00"&track_dbl(6 downto 1)  when "000000011",
			X"20"                       when "000000100",
			X"20"                       when "000000101",
			X"0F"                       when others;

	with byte_cnt select
		data_body <=
			X"07"     when "000000000",
			data_cks  when "100000001",
			X"00"     when "100000010",
			X"00"     when "100000011",
			X"0F"     when "100000100",
			X"0F"     when "100000101",
			X"0F"     when "100000110",
			X"0F"     when "100000111",
			X"0F"     when "100001000",
			X"0F"     when "100001001",
			X"0F"     when "100001010",
			X"0F"     when "100001011",
			X"0F"     when "100001100",
			X"0F"     when "100001101",
			X"0F"     when "100001110",
			X"0F"     when "100001111",
			X"0F"     when "100010000",
			X"0F"     when "100010001",
			track_din when others;
	
	with state select
		data <= data_header when '0',
		        data_body   when others;

	with nibble select
		gcr_nibble <= gcr_lut(to_integer(unsigned(data(7 downto 4)))) when '0',
		              gcr_lut(to_integer(unsigned(data(3 downto 0)))) when others;

	gcr_bit <= gcr_nibble(to_integer(unsigned(gcr_bit_cnt)));

	sector_max <=  "10100" when track_dbl(6 downto 1) < std_logic_vector(to_unsigned(18,6)) else 
                  "10010" when track_dbl(6 downto 1) < std_logic_vector(to_unsigned(25,6)) else
	               "10001" when track_dbl(6 downto 1) < std_logic_vector(to_unsigned(31,6)) else
 	               "10000" ;

	process (clk32)
		variable bit_clk_cnt : std_logic_vector(7 downto 0) := (others => '0');
	begin
		if rising_edge(clk32) then
			bit_clk_en <= '0';
			if bit_clk_cnt = X"6F" then
				bit_clk_en <= '1';
				bit_clk_cnt := (others => '0');
			else
				bit_clk_cnt := std_logic_vector(unsigned(bit_clk_cnt) + 1);
			end if;
			byte_n <= '1';
			if byte_in_n = '0' and mtr = '1' and track_ready = '1' then
				if bit_clk_cnt > X"10" then
					if bit_clk_cnt < X"5E" then
						byte_n <= '0';
					end if;
				end if;
			end if;
		end if;
	end process;

	process (clk32, bit_clk_en)
	begin
		if rising_edge(clk32) and bit_clk_en = '1' then
			if sync_in_n = '0'  then
				byte_cnt    <= (others => '0');
				nibble      <= '0';
				gcr_bit_cnt <= (others => '0');
				bit_cnt     <= (others => '0');
				do          <= (others => '0');
				gcr_byte    <= (others => '0');
				data_cks    <= (others => '0');
				if track_ready = '1' then
					if sync_cnt = X"31" then 
						sync_cnt <= (others => '0');
						sync_in_n <= '1';
					else
						sync_cnt <= std_logic_vector(unsigned(sync_cnt +1));
					end if;
				end if;
			else
				gcr_bit_cnt <= std_logic_vector(unsigned(gcr_bit_cnt)+1);
				if gcr_bit_cnt = X"4" then
					gcr_bit_cnt <= (others => '0');
					if nibble = '1' then 
						nibble   <= '0';
						byte_addr <= byte_cnt(7 downto 0);
						if byte_cnt = "000000000" then
							data_cks <= (others => '0');
						else
							data_cks <= data_cks xor data;
						end if;
						byte_cnt  <= std_logic_vector(unsigned(byte_cnt)+1);
					else
						nibble <= '1';
					end if;
				end if;
				bit_cnt <= std_logic_vector(unsigned(bit_cnt)+1);
				byte_in_n  <= '1';
				if bit_cnt = X"7" then
					byte_in_n <= '0';
				end if;
				if state = '0' then
					if byte_cnt = "000010000" then
						sync_in_n <= '0';
						state<= '1';
					end if;
				else
					if byte_cnt = "100010001" then 
						sync_in_n <= '0';
						state <= '0';
						if sector_dbl = sector_max then 
							sector_dbl <= (others=>'0');
						else
							sector_dbl <= std_logic_vector(unsigned(sector_dbl)+1);
						end if;
					end if;
				end if;
				gcr_byte <= gcr_byte(6 downto 0) & gcr_bit;
				if bit_cnt = X"7" then
					do <= gcr_byte(6 downto 0) & gcr_bit;
				end if;
			end if;
		end if;
	end process;

end struct;
