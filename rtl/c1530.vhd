---------------------------------------------------------------------------------
-- Commodore 1530 to SD card host (read only) by Dar (darfpga@aol.fr) 25-Mars-2019
-- http://darfpga.blogspot.fr
-- also darfpga on sourceforge
--
-- tap/wav player 
-- Converted to 8 bit FIFO - Slingshot
-- TAP v2 handle, format autodetect, remove WAV playback, fixes - Sorgelig
---------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;

entity c1530 is
port(
	clk      : in std_logic;
	restart  : in std_logic; -- keep to 1 to long enough to clear fifo
	                           -- reset tap header bytes skip counter

	clk_freq : in std_logic_vector(31 downto 0); -- frequency of clk
	cpu_freq : in std_logic_vector(31 downto 0); -- frequency of CPU

	din      : in std_logic_vector(7 downto 0);  -- 8bits fifo input
	wr       : in std_logic;     -- set to 1 for 1 clk to write 1 word
	full     : out std_logic;    -- do not write when fifo tap_fifo_full = 1
	empty    : buffer std_logic;    -- fifo fall empty (unrecoverable error)

	play     : in  std_logic;    -- 1 = read tape, 0 = stop reading 
	dout     : buffer std_logic  -- tape signal out 
);
end c1530;

architecture struct of c1530 is

signal tick_cnt   : std_logic_vector( 5 downto 0);
signal tap_dword  : std_logic_vector(31 downto 0);
signal wave_cnt   : std_logic_vector(23 downto 0);
signal wave_len   : std_logic_vector(23 downto 0);

signal fifo_dout  : std_logic_vector(7 downto 0);
signal fifo_rd    : std_logic;
signal fifo_empty : std_logic;
signal fifo_full  : std_logic;
signal get_24bits_len : std_logic;
signal start_bytes: std_logic_vector(7 downto 0);
signal skip_bytes : std_logic;
signal tap_mode   : std_logic_vector(1 downto 0);

begin

tap_fifo_inst : entity work.tap_fifo
port map(
	aclr	 => restart,
	data	 => din,
	clock	 => clk,
	rdreq	 => fifo_rd,
	wrreq	 => wr,
	q	    => fifo_dout,
	empty	 => fifo_empty,
	full	 => fifo_full
);

full <= fifo_full;

process(clk, restart)
variable
	sum : std_logic_vector(31 downto 0);
begin

	if restart = '1' then
		
		start_bytes <= X"00";
		skip_bytes <= '1';
		tick_cnt <= (others => '0');
		wave_len <= (others => '0');
		wave_cnt <= (others => '0');
		get_24bits_len <= '0';
		dout <= '1';

		fifo_rd <='0';
		empty <='0'; -- run out of data

	elsif rising_edge(clk) then

		fifo_rd <= '0';
		if play = '1' and empty = '0' then
			tick_cnt <= tick_cnt + 1;
			sum := sum + cpu_freq;
			if sum >= clk_freq then
				sum := sum - clk_freq;
				if skip_bytes = '0' then
					if tap_mode < 2 then
						-- square wave period (1/2 duty cycle not mendatory, only falling edge matter)
						if wave_cnt > '0'&wave_len(10 downto 1) then
							dout <= '1';
						else
							dout <= '0';
						end if;
					end if;

					tick_cnt <= (others => '0');
					wave_cnt <= wave_cnt + 1;

					if wave_cnt >= wave_len then
						wave_cnt <= (others => '0');
						if tap_mode = 2 then
							dout <= not dout;
						end if;
						if fifo_empty = '1' then
							empty <= '1';
							dout <= '1';
						else
							fifo_rd <= '1';
							if fifo_dout = x"00" then
								wave_len <= x"000100"; -- interpret data x00 for mode 0
								get_24bits_len <= tap_mode(0) or tap_mode(1);
							else
								wave_len <= '0'&x"000" & fifo_dout & "000";
							end if;
						end if;
					end if;
				end if;
			end if;

			-- catch 24bits wave_len for data x00 in tap mode 1/2
			if get_24bits_len = '1' and skip_bytes = '0' and tick_cnt(0) = '1' then
				if tick_cnt = 5 then 
					get_24bits_len <= '0';
					if((fifo_dout & wave_len(23 downto 8)) > clk_freq) then
						dout <= '1';
					end if;
				end if;
				if fifo_empty = '1' then
					empty <= '1';
					dout <= '1';
				else
					fifo_rd <= '1';			
					wave_len <= fifo_dout & wave_len(23 downto 8);
				end if;
			end if;

			-- skip tap header bytes
			if skip_bytes = '1' and fifo_full = '1' and tick_cnt(0) = '1' then
				fifo_rd <= '1';
				if start_bytes = 13 then
					tap_mode <= fifo_dout(1 downto 0);
				end if;
				if ((start_bytes < 20) and (tap_mode = 2)) or ((start_bytes < 26) and (tap_mode /= 2)) then
					start_bytes <= start_bytes + 1;
				else
					skip_bytes <= '0';
				end if;
			end if;
		end if;
	end if;
end process;

end struct;

LIBRARY ieee;
USE ieee.std_logic_1164.all;

ENTITY tap_fifo IS
	PORT
	(
		aclr  : IN  STD_LOGIC;
		clock : IN  STD_LOGIC;
		data  : IN  STD_LOGIC_VECTOR (7 DOWNTO 0);
		rdreq : IN  STD_LOGIC;
		wrreq : IN  STD_LOGIC;
		empty : OUT STD_LOGIC;
		full  : OUT STD_LOGIC;
		q     : OUT STD_LOGIC_VECTOR (7 DOWNTO 0)
	);
END tap_fifo;

ARCHITECTURE SYN OF tap_fifo IS

	COMPONENT scfifo
	GENERIC
	(
		add_ram_output_register : STRING;
		intended_device_family  : STRING;
		lpm_numwords            : NATURAL;
		lpm_showahead           : STRING;
		lpm_type                : STRING;
		lpm_width               : NATURAL;
		lpm_widthu              : NATURAL;
		overflow_checking       : STRING;
		underflow_checking      : STRING;
		use_eab                 : STRING
	);
	PORT
	(
		aclr  : IN  STD_LOGIC;
		clock : IN  STD_LOGIC;
		data  : IN  STD_LOGIC_VECTOR (7 DOWNTO 0);
		rdreq : IN  STD_LOGIC;
		empty : OUT STD_LOGIC;
		full  : OUT STD_LOGIC;
		q     : OUT STD_LOGIC_VECTOR (7 DOWNTO 0);
		wrreq : IN  STD_LOGIC 
	);
	END COMPONENT;

BEGIN
	scfifo_component : scfifo
	GENERIC MAP
	(
		add_ram_output_register => "OFF",
		intended_device_family => "Cyclone III",
		lpm_numwords => 64,
		lpm_showahead => "OFF",
		lpm_type => "scfifo",
		lpm_width => 8,
		lpm_widthu => 6,
		overflow_checking => "ON",
		underflow_checking => "ON",
		use_eab => "ON"
	)
	PORT MAP
	(
		aclr  => aclr,
		clock => clock,
		data  => data,
		rdreq => rdreq,
		wrreq => wrreq,
		empty => empty,
		full  => full,
		q     => q
	);
END SYN; 
