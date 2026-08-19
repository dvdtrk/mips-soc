module data_memory_64B (
	input  logic        clock_dm,
	input  logic        reset_dm,
	input  logic [31:0] address_dm,
	input  logic [31:0] Writedata_dm,
	input  logic        memory_read_dm,
	input  logic        memory_write_dm,
	output logic [31:0] Readdata_dm
);

	logic [31:0] RAM [0:47];

	initial begin
		for (int k = 0; k < 48; k++)
			RAM[k] = 32'h00000000;

		// operand A and B
		RAM[33] = 32'hc0000ff0; // ADDR 84
		RAM[34] = 32'h80001010; // ADDR 88

		// the following locations contain zero initially but will hold these
		// values after execution:
		// 35 / ADDR 8c: result of 000a0ff0 "add" 00001010
		// 36 / ADDR 90: result of 000a0ff0 "sub" 00001010
		// 37 / ADDR 94: result of 000a0ff0 "and" 00001010
		// 38 / ADDR 98: result of 000a0ff0 "nor" 00001010
		// 39 / ADDR 9c: result of 000a0ff0 "slt" 00001010
	end

	// synchronous write (word-addressed: address_dm/4)
	always_ff @(posedge clock_dm) begin
		if (memory_write_dm)
			RAM[address_dm[31:2]] <= Writedata_dm;
	end

	// asynchronous read
	assign Readdata_dm = memory_read_dm ? RAM[address_dm[31:2]] : 32'h00000000;

endmodule