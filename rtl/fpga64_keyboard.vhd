-- -----------------------------------------------------------------------
--
--                                 FPGA 64
--
--     A fully functional commodore 64 implementation in a single FPGA
--
-- -----------------------------------------------------------------------
-- Copyright 2005-2008 by Peter Wendrich (pwsoft@syntiac.com)
-- http://www.syntiac.com/fpga64.html
-- -----------------------------------------------------------------------
-- 'Joystick emulation on keypad' additions by
-- Mark McDougall (msmcdoug@iinet.net.au)
-- -----------------------------------------------------------------------
--
-- VIC20/C64 Keyboard matrix
--
-- Hardware huh?
--	In original machine if a key is pressed a contact is made.
--	Bidirectional reading is possible on real hardware, which is difficult
--	to emulate. (set backwardsReadingEnabled to '1' if you want this enabled).
--	Then we have the joysticks, one of which is normally connected
--	to a OUTPUT pin.
--
-- Emulation:
--	All pins are high except when one is driven low and there is a
--	connection. This is consistent with joysticks that force a line
--	low too. CIA will put '1's when set to input to help this emulation.
--
-- -----------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.std_logic_unsigned.ALL;
use IEEE.numeric_std.ALL;

entity fpga64_keyboard is
	port (
		clk     : in std_logic;
		reset   : in std_logic;
		
		ps2_key : in std_logic_vector(10 downto 0);
		joyA    : in unsigned(6 downto 0);
		joyB    : in unsigned(6 downto 0);
		
		shift_mod: in std_logic_vector(1 downto 0);

		pai     : in unsigned(7 downto 0);
		pbi     : in unsigned(7 downto 0);
		pao     : out unsigned(7 downto 0);
		pbo     : out unsigned(7 downto 0);
		
		restore_key : out std_logic;
		mod_key     : out std_logic;
		tape_play   : out std_logic;
		
		-- Config
		-- backwardsReadingEnabled = 1 allows reversal of PIA registers to still work.
		-- not needed for kernel/normal operation only for some specific programs.
		-- set to 0 to save some hardware.
		backwardsReadingEnabled : in std_logic
	);
end fpga64_keyboard;

architecture rtl of fpga64_keyboard is	
	signal extended: boolean;
	signal pressed: std_logic := '0';

	signal key_del: std_logic := '0';
	signal key_return: std_logic := '0';
	signal key_left: std_logic := '0';
	signal key_right: std_logic := '0';
	signal key_F1: std_logic := '0';
	signal key_F2: std_logic := '0';
	signal key_F3: std_logic := '0';
	signal key_F4: std_logic := '0';
	signal key_F5: std_logic := '0';
	signal key_F6: std_logic := '0';
	signal key_F7: std_logic := '0';
	signal key_F8: std_logic := '0';
	signal key_up: std_logic := '0';
	signal key_down: std_logic := '0';

	signal key_3: std_logic := '0';
	signal key_W: std_logic := '0';
	signal key_A: std_logic := '0';
	signal key_4: std_logic := '0';
	signal key_Z: std_logic := '0';
	signal key_S: std_logic := '0';
	signal key_E: std_logic := '0';
	signal key_shiftl: std_logic := '0';

	signal key_5: std_logic := '0';
	signal key_R: std_logic := '0';
	signal key_D: std_logic := '0';
	signal key_6: std_logic := '0';
	signal key_C: std_logic := '0';
	signal key_F: std_logic := '0';
	signal key_T: std_logic := '0';
	signal key_X: std_logic := '0';
	
	signal key_7: std_logic := '0';
	signal key_Y: std_logic := '0';
	signal key_G: std_logic := '0';
	signal key_8: std_logic := '0';
	signal key_B: std_logic := '0';
	signal key_H: std_logic := '0';
	signal key_U: std_logic := '0';
	signal key_V: std_logic := '0';

	signal key_9: std_logic := '0';
	signal key_I: std_logic := '0';
	signal key_J: std_logic := '0';
	signal key_0: std_logic := '0';
	signal key_M: std_logic := '0';
	signal key_K: std_logic := '0';
	signal key_O: std_logic := '0';
	signal key_N: std_logic := '0';

	signal key_plus: std_logic := '0';
	signal key_P: std_logic := '0';
	signal key_L: std_logic := '0';
	signal key_minus: std_logic := '0';
	signal key_dot: std_logic := '0';
	signal key_colon: std_logic := '0';
	signal key_at: std_logic := '0';
	signal key_comma: std_logic := '0';

	signal key_pound: std_logic := '0';
	signal key_star: std_logic := '0';
	signal key_semicolon: std_logic := '0';
	signal key_home: std_logic := '0';
	signal key_shiftr: std_logic := '0';
	signal key_equal: std_logic := '0';
	signal key_arrowup: std_logic := '0';
	signal key_slash: std_logic := '0';

	signal key_1: std_logic := '0';
	signal key_arrowleft: std_logic := '0';
	signal key_ctrl: std_logic := '0';
	signal key_2: std_logic := '0';
	signal key_space: std_logic := '0';
	signal key_commodore: std_logic := '0';
	signal key_Q: std_logic := '0';
	signal key_runstop: std_logic := '0';

	signal mod_key1: std_logic := '0';
	signal mod_key2: std_logic := '0';

	signal key_shift: std_logic := '0';
	signal key_inst: std_logic := '0';
	signal key_caps: std_logic := '0';
	
	-- for joystick emulation on PS2
	signal old_state : std_logic;
	
	signal delay_cnt : integer range 0 to 300000;
	signal delay_end : std_logic;
	signal ps2_stb   : std_logic;
	signal key_8s    : std_logic := '0';

begin

	delay_end <= '1' when delay_cnt = 0 else '0';

	pressed <= ps2_key(9);
	extended<= ps2_key(8) = '1';

	mod_key <= mod_key1 or mod_key2;
	key_shift <= key_shiftl or key_shiftr;
	
	matrix: process(clk)
	begin
		if rising_edge(clk) then
		
			ps2_stb <= ps2_key(10);

			if delay_cnt /= 0 then
				delay_cnt <= delay_cnt - 1;
			end if;

			-- reading A, scan pattern on B
			pao(0) <= pai(0) and joyB(0) and
				((not backwardsReadingEnabled) or
				((pbi(0) or not (key_del or key_inst)) and
				(pbi(1) or not key_return) and
				(pbi(2) or not (key_left or key_right)) and
				(pbi(3) or not (key_F7 or key_F8)) and
				(pbi(4) or not (key_F1 or key_F2)) and
				(pbi(5) or not (key_F3 or key_F4)) and
				(pbi(6) or not (key_F5 or key_F6)) and
				(pbi(7) or not (key_up or key_down))));
			pao(1) <= pai(1) and joyB(1) and
				((not backwardsReadingEnabled) or
				((pbi(0) or not key_3) and
				(pbi(1) or not key_W) and
				(pbi(2) or not key_A) and
				(pbi(3) or not key_4) and
				(pbi(4) or not key_Z) and
				(pbi(5) or not key_S) and
				(pbi(6) or not key_E) and
				(pbi(7) or not (((key_left or key_up or key_caps or key_inst or key_F2 or key_F4 or key_F6 or key_F8) and shift_mod(1)) or (key_shiftl and not key_8s)))));
			pao(2) <= pai(2) and joyB(2) and
				((not backwardsReadingEnabled) or
				((pbi(0) or not key_5) and
				(pbi(1) or not key_R) and
				(pbi(2) or not key_D) and
				(pbi(3) or not key_6) and
				(pbi(4) or not key_C) and
				(pbi(5) or not key_F) and
				(pbi(6) or not key_T) and
				(pbi(7) or not key_X)));
			pao(3) <= pai(3) and joyB(3) and
				((not backwardsReadingEnabled) or
				((pbi(0) or not key_7) and
				(pbi(1) or not key_Y) and
				(pbi(2) or not key_G) and
				(pbi(3) or not key_8) and
				(pbi(4) or not key_B) and
				(pbi(5) or not key_H) and
				(pbi(6) or not key_U) and
				(pbi(7) or not key_V)));
			pao(4) <= pai(4) and joyB(4) and
				((not backwardsReadingEnabled) or
				((pbi(0) or not key_9) and
				(pbi(1) or not key_I) and
				(pbi(2) or not key_J) and
				(pbi(3) or not key_0) and
				(pbi(4) or not key_M) and
				(pbi(5) or not key_K) and
				(pbi(6) or not key_O) and
				(pbi(7) or not key_N)));
			pao(5) <= pai(5) and
				((not backwardsReadingEnabled) or
				((pbi(0) or not key_plus) and
				(pbi(1) or not key_P) and
				(pbi(2) or not key_L) and
				(pbi(3) or not key_minus) and
				(pbi(4) or not key_dot) and
				(pbi(5) or not key_colon) and
				(pbi(6) or not key_at) and
				(pbi(7) or not key_comma)));
			pao(6) <= pai(6) and
				((not backwardsReadingEnabled) or
				((pbi(0) or not key_pound) and
				(pbi(1) or not (key_star or (key_8s and delay_end))) and
				(pbi(2) or not key_semicolon) and
				(pbi(3) or not key_home) and
				(pbi(4) or not (((key_left or key_up or key_caps or key_inst or key_F2 or key_F4 or key_F6 or key_F8) and shift_mod(0)) or (key_shiftr and not key_8s))) and
				(pbi(5) or not key_equal) and
				(pbi(6) or not key_arrowup) and
				(pbi(7) or not key_slash)));
			pao(7) <= pai(7) and
				((not backwardsReadingEnabled) or
				((pbi(0) or not key_1) and
				(pbi(1) or not key_arrowleft) and
				(pbi(2) or not (key_ctrl or not joyA(6) or not joyB(6))) and
				(pbi(3) or not key_2) and
				(pbi(4) or not (key_space or not joyA(5) or not joyB(5))) and
				(pbi(5) or not (key_commodore or key_caps)) and
				(pbi(6) or not key_Q) and
				(pbi(7) or not key_runstop)));

			-- reading B, scan pattern on A
			pbo(0) <= pbi(0) and joyA(0) and 
				(pai(0) or not (key_del or key_inst)) and
				(pai(1) or not key_3) and
				(pai(2) or not key_5) and
				(pai(3) or not key_7) and
				(pai(4) or not key_9) and
				(pai(5) or not key_plus) and
				(pai(6) or not key_pound) and
				(pai(7) or not key_1);
			pbo(1) <= pbi(1) and joyA(1) and
				(pai(0) or not key_return) and
				(pai(1) or not key_W) and
				(pai(2) or not key_R) and
				(pai(3) or not key_Y) and
				(pai(4) or not key_I) and
				(pai(5) or not key_P) and
				(pai(6) or not (key_star or (key_8s and delay_end))) and
				(pai(7) or not key_arrowleft);
			pbo(2) <= pbi(2) and joyA(2) and
				(pai(0) or not (key_left or key_right)) and
				(pai(1) or not key_A) and
				(pai(2) or not key_D) and
				(pai(3) or not key_G) and
				(pai(4) or not key_J) and
				(pai(5) or not key_L) and
				(pai(6) or not key_semicolon) and
				(pai(7) or not (key_ctrl or not joyA(6) or not joyB(6)));
			pbo(3) <= pbi(3) and joyA(3) and
				(pai(0) or not (key_F7 or key_F8)) and
				(pai(1) or not key_4) and
				(pai(2) or not key_6) and
				(pai(3) or not key_8) and
				(pai(4) or not key_0) and
				(pai(5) or not key_minus) and
				(pai(6) or not key_home) and
				(pai(7) or not key_2);
			pbo(4) <= pbi(4) and joyA(4) and
				(pai(0) or not (key_F1 or key_F2)) and
				(pai(1) or not key_Z) and
				(pai(2) or not key_C) and
				(pai(3) or not key_B) and
				(pai(4) or not key_M) and
				(pai(5) or not key_dot) and
				(pai(6) or not (((key_left or key_up or key_caps or key_inst or key_F2 or key_F4 or key_F6 or key_F8) and shift_mod(0)) or (key_shiftr and not key_8s))) and
				(pai(7) or not (key_space or not joyA(5) or not joyB(5)));
			pbo(5) <= pbi(5) and
				(pai(0) or not (key_F3 or key_F4)) and
				(pai(1) or not key_S) and
				(pai(2) or not key_F) and
				(pai(3) or not key_H) and
				(pai(4) or not key_K) and
				(pai(5) or not key_colon) and
				(pai(6) or not key_equal) and
				(pai(7) or not (key_commodore or key_caps));
			pbo(6) <= pbi(6) and
				(pai(0) or not (key_F5 or key_F6)) and
				(pai(1) or not key_E) and
				(pai(2) or not key_T) and
				(pai(3) or not key_U) and
				(pai(4) or not key_O) and
				(pai(5) or not key_at) and
				(pai(6) or not key_arrowup) and
				(pai(7) or not key_Q);
			pbo(7) <= pbi(7) and
				(pai(0) or not (key_up or key_down)) and
				(pai(1) or not (((key_left or key_up or key_caps or key_inst or key_F2 or key_F4 or key_F6 or key_F8) and shift_mod(1)) or (key_shiftl and not key_8s))) and
				(pai(2) or not key_X) and
				(pai(3) or not key_V) and
				(pai(4) or not key_N) and
				(pai(5) or not key_comma) and
				(pai(6) or not key_slash) and
				(pai(7) or not key_runstop);

			if ps2_key(10) /= ps2_stb then
				case ps2_key(7 downto 0) is
					when X"05" => key_F1 <= pressed;
					when X"06" => key_F2 <= pressed;
					when X"04" => key_F3 <= pressed;
					when X"0C" => key_F4 <= pressed;
					when X"03" => key_F5 <= pressed;
					when X"0B" => key_F6 <= pressed;
					when X"83" => key_F7 <= pressed;
					when X"0A" => key_F8 <= pressed;
					when X"01" => key_arrowup <= pressed; -- F9
					when X"09" => key_equal <= pressed; -- F10
					when X"0D" => key_commodore <= pressed; 
					when X"0E" => key_arrowleft <= pressed;
					when X"11" => key_commodore <= pressed; 
					when X"12" => key_shiftl <= pressed;
					when X"14" => key_ctrl <= pressed; 
					when X"15" => key_Q <= pressed; 
					when X"16" => key_1 <= pressed; 
					when X"1A" => key_Z <= pressed; 
					when X"1B" => key_S <= pressed; 
					when X"1C" => key_A <= pressed; 
					when X"1D" => key_W <= pressed; 
					when X"1E" => key_2 <= pressed; 
					when X"1F" => mod_key1 <= pressed; 
					when X"21" => key_C <= pressed; 
					when X"22" => key_X <= pressed; 
					when X"23" => key_D <= pressed; 
					when X"24" => key_E <= pressed; 
					when X"25" => key_4 <= pressed; 
					when X"26" => key_3 <= pressed; 
					when X"27" => mod_key2 <= pressed; 
					when X"29" => key_space <= pressed; 
					when X"2A" => key_V <= pressed; 
					when X"2B" => key_F <= pressed; 
					when X"2C" => key_T <= pressed; 
					when X"2D" => key_R <= pressed; 
					when X"2E" => key_5 <= pressed; 
					when X"31" => key_N <= pressed; 
					when X"32" => key_B <= pressed; 
					when X"33" => key_H <= pressed; 
					when X"34" => key_G <= pressed; 
					when X"35" => key_Y <= pressed; 
					when X"36" => key_7 <= pressed and     key_shift;
									  key_6 <= pressed and not key_shift;
					when X"3A" => key_M <= pressed; 
					when X"3B" => key_J <= pressed; 
					when X"3C" => key_U <= pressed; 
					when X"3D" => key_6 <= pressed and     key_shift;
									  key_7 <= pressed and not key_shift;
					when X"3E" => key_8s <= pressed and    key_shift;
									  key_8 <= pressed and not key_shift;
									  delay_cnt <= 300000;
					when X"41" => key_comma <= pressed; 
					when X"42" => key_K <= pressed;
					when X"43" => key_I <= pressed; 
					when X"44" => key_O <= pressed; 
					when X"45" => key_9 <= pressed and     key_shift;
									  key_0 <= pressed and not key_shift;
					when X"46" => key_8 <= pressed and     key_shift;
									  key_9 <= pressed and not key_shift;
					when X"49" => key_dot <= pressed; 
					when X"4A" => key_slash <= pressed; 
					when X"4B" => key_L <= pressed; 
					when X"4C" => key_colon <= pressed; 
					when X"4D" => key_P <= pressed; 
					when X"4E" => key_minus <= pressed;
					when X"52" => key_semicolon <= pressed; 
					when X"54" => key_at <= pressed; 
					when X"55" => key_plus <= pressed;
					when X"58" => key_caps <= pressed;
					when X"59" => key_shiftr <= pressed;
					when X"5A" => key_Return <= pressed; 
					when X"5B" => key_star <= pressed; 
					when X"5D" => key_pound <= pressed;
					when X"66" => key_del <= pressed; 
					when X"69" => if extended then key_equal   <= pressed; else key_1   <= pressed; end if;
					when X"6B" => if extended then key_left    <= pressed; else key_4   <= pressed; end if;
					when X"6C" => if extended then key_home    <= pressed; else key_7   <= pressed; end if;
					when X"70" => if extended then key_inst    <= pressed; else key_0   <= pressed; end if;
					when X"71" => if extended then key_del     <= pressed; else key_dot <= pressed; end if;
					when X"72" => if extended then key_down    <= pressed; else key_2   <= pressed; end if;
					when X"73" => key_5 <= pressed; 
					when X"74" => if extended then key_right   <= pressed; else key_6   <= pressed; end if;
					when X"75" => if extended then key_up      <= pressed; else key_8   <= pressed; end if;
					when X"76" => key_runstop <= pressed; 
					when X"78" => restore_key <= pressed; -- F11
					when X"79" => key_plus <= pressed; 
					when X"7A" => if extended then key_arrowup <= pressed; else key_3   <= pressed; end if;
					when X"7B" => key_minus <= pressed; 
					when X"7C" => key_star <= pressed; 
					when X"7D" => if extended then tape_play <= pressed; else key_9   <= pressed; end if;
					when others => null;
				end case;
			end if;
			
			if reset = '1' then
					key_F1        <= '0';
					key_F2        <= '0';
					key_F3        <= '0';
					key_F4        <= '0';
					key_F5        <= '0';
					key_F6        <= '0';
					key_F7        <= '0';
					key_F8        <= '0';
					key_shiftr    <= '0';
					key_shiftl    <= '0';
					key_ctrl      <= '0'; 
					mod_key1      <= '0'; 
					mod_key2      <= '0'; 
					key_commodore <= '0'; 
					key_runstop   <= '0';
					restore_key   <= '0';
					tape_play     <= '0';
					key_arrowup   <= '0';
					key_equal     <= '0';
					key_arrowleft <= '0';
					key_space     <= '0'; 
					key_comma     <= '0';
					key_dot       <= '0'; 
					key_slash     <= '0'; 
					key_colon     <= '0'; 
					key_minus     <= '0';
					key_semicolon <= '0'; 
					key_at        <= '0'; 
					key_plus      <= '0';
					key_caps      <= '0';
					key_Return    <= '0'; 
					key_star      <= '0'; 
					key_pound     <= '0';
					key_del       <= '0'; 
					key_left      <= '0';
					key_home      <= '0';
					key_inst      <= '0';
					key_down      <= '0';
					key_right     <= '0';
					key_up        <= '0';
					key_1         <= '0'; 
					key_2         <= '0'; 
					key_3         <= '0'; 
					key_4         <= '0'; 
					key_5         <= '0'; 
					key_6         <= '0';
					key_7         <= '0';
					key_8         <= '0';
					key_8s        <= '0';
					key_9         <= '0';
					key_0         <= '0';
					key_Q         <= '0'; 
					key_Z         <= '0'; 
					key_S         <= '0'; 
					key_A         <= '0'; 
					key_W         <= '0'; 
					key_C         <= '0'; 
					key_X         <= '0'; 
					key_D         <= '0'; 
					key_E         <= '0'; 
					key_V         <= '0'; 
					key_F         <= '0'; 
					key_T         <= '0'; 
					key_R         <= '0'; 
					key_N         <= '0'; 
					key_B         <= '0'; 
					key_H         <= '0'; 
					key_G         <= '0'; 
					key_Y         <= '0'; 
					key_M         <= '0';
					key_J         <= '0';
					key_U         <= '0';
					key_K         <= '0';
					key_I         <= '0';
					key_O         <= '0';
					key_L         <= '0'; 
					key_P         <= '0'; 
			end if;
		end if;
	end process;
end architecture;
