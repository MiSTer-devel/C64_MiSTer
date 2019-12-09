//-------------------------------------------------------------------------------
//
// Reworked and adapted to MiSTer by Sorgelig@MiSTer (07.09.2018)
//
// Commodore 1541 gcr floppy (read/write) by Dar (darfpga@aol.fr) 23-May-2017
// http://darfpga.blogspot.fr
//
// produces GCR data, byte(ready) and sync signal to feed c1541_logic from current
// track buffer ram which contains D64 data
//
// gets GCR data from c1541_logic, while producing byte(ready) signal. Data feed
// track buffer ram after conversion
//
// Input clk 32MHz
//
//-------------------------------------------------------------------------------

module sn74ls193 (
	input            clk,

	input            up,
	input            down,
	input      [3:0] data_in,
	input            clr,
	input            load_n,

	output reg       carry_n,
	output reg       borrow_n,
	output reg [3:0] data_out
);
always @(posedge clk) begin
	reg up1, down1;
	up1 <= up;
	down1 <= down;
	borrow_n <= |{down, data_out};
	carry_n <= ~&{data_out, ~up};
	if (clr) data_out <= 4'b0;
	else if (~load_n) data_out <= data_in;
	else if (up1 && ~up) data_out <= data_out + 4'b1;
	else if (down1 && ~down) data_out <= data_out - 4'b1;
	// else, no change
end
endmodule

module c1541_gcr
(
	input            clk32,
	output     [7:0] dout,    // data from ram to 1541 logic
	input      [7:0] din,     // data from 1541 logic to ram
	input            mode,    // read/write
	input            soe,     // serial output enable
	input            wps_n,   // write-protect
	input      [1:0] freq,    // motor (gcr_bit) frequency
	output           sync_n,  // reading SYNC bytes
	output reg       byte_n,  // byte ready

	input      [5:0] track,

	input            ram_do,
	output reg       ram_di,
	output reg       ram_we,
	input            ram_ready
);

reg clk16; // c1541 internal crystal
always @(posedge clk32) clk16 <= ~clk16;

reg read_data;
always @(posedge clk32) begin
	reg ram_do1;
	reg [6:0] time_domain_filter_counter;
	reg time_domain_filter_out1;
	reg [2:0] one_shot_counter;
	ram_do1 <= ram_do;

	// Time domain filter times out after about 41 16MHz cycles.
	if (ram_do && !ram_do1)
		time_domain_filter_counter <= 7'd82;
	else if (time_domain_filter_counter)
		time_domain_filter_counter <= time_domain_filter_counter - 7'b1;
	// else: stable state, stay at 0

	// One-shot counter times out after 2 16MHz cycles.
	time_domain_filter_out1 <= |time_domain_filter_counter;
	if (|time_domain_filter_counter && !time_domain_filter_out1)
		one_shot_counter <= 3'd4;
	else if (one_shot_counter)
		one_shot_counter <= one_shot_counter - 3'b1;
	// else: stable state, stay at 0

	read_data <= |one_shot_counter;
end

wire raw_bit_clock; // speed-zone-adjusted clock
sn74ls193 raw_bit_clock_ic(
	.clk(clk32),
	.up(clk16),
	.down(1'b1),
	.data_in({2'b0, freq}),
	.clr(1'b0),
	.load_n(raw_bit_clock & ~read_data),

	.carry_n(raw_bit_clock),
	.borrow_n(),
	.data_out()
);

// state counter:
// state[0] clocks parallel input on byte boundary and high state[1]
// state[1] clocks bit counter, bit shifters, and when low clocks byte ready
//          and is mixed with serial output
// state[3:2] counts how many bits ago a magnetic flux inversion was last
//            sensed.
wire [3:0] state;
sn74ls193 state_counter_ic(
	.clk(clk32),
	.up(~raw_bit_clock),
	.down(1'b1),
	.data_in(4'b0),
	.clr(read_data),
	.load_n(1'b1),

	.carry_n(),
	.borrow_n(),
	.data_out(state)
);

reg parallel_to_serial_load_edge;
reg bit_clock_posedge;
reg bit_clock_negedge;
always @(posedge clk32) begin
	reg parallel_to_serial_load1;
	reg bit_clock1;
	bit_clock1 <= state[1];
	bit_clock_negedge <= bit_clock1 && !state[1];
	bit_clock_posedge <= !bit_clock1 && state[1];
	parallel_to_serial_load1 <= parallel_to_serial_load;
	parallel_to_serial_load_edge <= !parallel_to_serial_load1 && parallel_to_serial_load;
end

reg [2:0] bit_count;
wire whole_byte = &bit_count;
wire parallel_to_serial_load = &{whole_byte, state[1], state[0]};
reg [9:0] read_shift_register;
reg [7:0] write_shift_register;
assign dout = read_shift_register[7:0];

always @(posedge clk32) begin
	sync_n <= ~&{mode, read_shift_register};
	ram_di <= write_shift_register[7] & ~state[1];
	if (bit_clock_posedge) begin
		bit_count <= sync_n ? bit_count + 3'b1 : 3'b0;
		read_shift_register <= {read_shift_register[8:0], ~|state[3:2]};
		write_shift_register <= {write_shift_register[6:0], 1'b0};
		ram_we <= (~mode && wps_n);
	end
	if (bit_clock_negedge) begin
		byte_n <= ~&{whole_byte, soe};
	end
	if (parallel_to_serial_load_edge) begin
		write_shift_register <= din;
	end
end

endmodule
