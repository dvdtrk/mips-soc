module ALU_32 (
	input  logic [31:0] A_alu32,          // A input
	input  logic [31:0] B_alu32,          // B input
	input  logic [3:0]  ALUctl_alu32,     // control
	output logic [31:0] ALUresult_alu32,  // result
	output logic        overflow_alu32,   // overflow (stub, matches original, always 0)
	output logic        Zero_alu32        // check if ALUresult is zero
);

	logic set;
	logic [31:0] ALU_result;
	logic [31:0] c_in;
	logic [31:0] c_out;

	// c_in(0): Binvert bit also seeds the carry-in for two's-complement subtraction
	assign c_in[0] = ALUctl_alu32[2];

	// bit 0 uses 'set' as its less_alu input (this is where slt's result bit lives)
	ALU ALU_0 (
		.A_alu        (A_alu32[0]),
		.B_alu        (B_alu32[0]),
		.ALUctl_alu   (ALUctl_alu32),
		.ALUresult_alu(ALU_result[0]),
		.carryout_alu (c_out[0]),
		.carryin_alu  (c_in[0]),
		.less_alu     (set)
	);

	genvar i;
	generate
		for (i = 1; i <= 31; i++) begin : alubits
			ALU ALU_i (
				.A_alu        (A_alu32[i]),
				.B_alu        (B_alu32[i]),
				.ALUctl_alu   (ALUctl_alu32),
				.ALUresult_alu(ALU_result[i]),
				.carryout_alu (c_out[i]),
				.carryin_alu  (c_in[i]),
				.less_alu     (1'b0)
			);
			assign c_in[i] = c_out[i-1];
		end
	endgenerate

	assign Zero_alu32      = (ALU_result == 32'h00000000);
	assign set              = A_alu32[31] ^ (~B_alu32[31]) ^ c_out[30]; // slt sign logic
	assign ALUresult_alu32  = ALU_result;
	assign overflow_alu32   = 1'b0; // stub in original VHDL too, never actually computed

endmodule