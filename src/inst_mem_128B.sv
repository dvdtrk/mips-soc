module inst_memory_128B (
	input  logic        clock_im,
	input  logic        reset_im,
	input  logic [31:0] pc_im,
	output logic [31:0] instruction_im
);

	// Test program #4 tests beq, bne and j instructions (forward/backward direction)
	// It should perform in this sequence:
	// (instruction number in parenthesis; see instruction sequence below)
	// 28(10, beq) --> 2C(11, add) --> 30(12, add) --> 34(13, add) --> 38(14, j) -->
	// 40(16, beq) --> 4C(19, add) --> 50(20, beq) --> 28(10, beq) --> 3C(15, j) --> 54(21, add)

	logic [31:0] ROM [0:47];

	initial begin
		// Registers and DM contain values from a previous execution when reset.
		// At the end of the program, include an instruction sequence to reset them.

		// Top:
		ROM[0]  = 32'h00000020; // add $0, $0, $0
		ROM[1]  = 32'h8ca20000; // lw  $2  0($5)
		ROM[2]  = 32'h8ca30004; // lw  $3  4($5)
		ROM[3]  = 32'h00000020; // nop
		ROM[4]  = 32'h00000020; // nop
		ROM[5]  = 32'h00435020; // add $10 $2 $3
		ROM[6]  = 32'h00435822; // sub $11 $2 $3
		ROM[7]  = 32'h00000020; // nop
		ROM[8]  = 32'hacca0000; // sw  $10 0($6)
		ROM[9]  = 32'haccb0004; // sw  $11 4($6)
		ROM[10] = 32'h8cc10000; // lw  $1  0($6)
		ROM[11] = 32'h8cc10004; // lw  $1  4($6)

		// put this code at the end
		ROM[12] = 32'hACC00000; // sw $0, 0($6)
		ROM[13] = 32'hACC00004; // sw $0, 4($6)
		ROM[14] = 32'h00005020; // add $10, $0, $0
		ROM[15] = 32'h00005820; // add $11, $0, $0
		ROM[16] = 32'h00000820; // add $1, $0, $0
		ROM[17] = 32'h00001020; // add $2, $0, $0
		ROM[18] = 32'h00001820; // add $3, $0, $0

		// ------------------------------------------------------------------
		// Test program #2 tests beq, bne and j instructions (backward direction)
		// Check the PC (program counter) at the IF stage; it should follow:
		// 50(20), 54(21), 58(22), 5C(23), 60(24), 64, 70, 74, 78, 7C, 84,
		// 88, 8C, 90, 94, 50, 54, 58, 5C, 68, 6C, 98

		ROM[19] = 32'h00C01820; // add $3, $6, $0 -- save $6

		ROM[20] = 32'h10a60005; // 50 [ beq $5 $6 Label1 ]
		ROM[21] = 32'h00000020; // 54 [ add $0 $0 $0 ]
		ROM[22] = 32'h00000020; // 58 [ add $0 $0 $0 ]
		ROM[23] = 32'h00000020; // 5C [ add $0 $0 $0 ]
		ROM[24] = 32'h0800001C; // 60 [ j Label2 ]
		ROM[25] = 32'h00000020; // 64 [ add $0 $0 $0 ]
		// Label1:
		ROM[26] = 32'h08000026; // 68 [ j Label4 ]
		ROM[27] = 32'h00000020; // 6C [ add $0 $0 $0 ]
		// Label2:
		ROM[28] = 32'h10a50004; // 70 [ beq $5 $5 Label3 ]
		ROM[29] = 32'h00000020; // 74 [ add $0 $0 $0 ]
		ROM[30] = 32'h00000020; // 78 [ add $0 $0 $0 ]
		ROM[31] = 32'h00000020; // 7C [ add $0 $0 $0 ]
		ROM[32] = 32'h00000020; // 80 [ add $0 $0 $0 ]
		// Label3:
		ROM[33] = 32'h00a030a0; // 84 [ add $6 $5 $0 ]
		ROM[34] = 32'h10a5fff1; // 88 [ beq $5 $5 Top ]
		ROM[35] = 32'h00000020; // 8C [ add $0 $0 $0 ]
		ROM[36] = 32'h00000020; // 90 [ add $0 $0 $0 ]
		ROM[37] = 32'h00000020; // 94 [ add $0 $0 $0 ]
		// Label4:
		ROM[38] = 32'h00000020; // 98 [ add $0 $0 $0 ]
		ROM[39] = 32'h00603020; // 9C add $6, $3, $0 -- restore $6
		ROM[40] = 32'h00001820; // A0 add $3, $0, $0

		// ------------------------------------------------------------------
		// Hazard/forwarding test: no manual filler instructions here on
		// purpose, unlike the tests above. This exercises the load-use
		// stall and the EX/MEM and MEM/WB forwarding paths for real,
		// instead of relying on hand-placed nops the way earlier lw
		// sequences in this file do.
		ROM[41] = 32'h8ca20000; // A4 lw  $2, 0($5), $2 = 0xc0000ff0
		ROM[42] = 32'h00421820; // A8 add $3, $2, $2, load-use hazard, must stall
		ROM[43] = 32'haca30004; // AC sw  $3, 4($5), needs forwarded $3, not stale data
		ROM[44] = 32'h00603020; // B0 add $6, $3, $0, needs forwarded $3
		ROM[45] = 32'h8ca70004; // B4 lw  $7, 4($5), reloads what was just stored,
		                        //    confirming the store used the forwarded value
		ROM[46] = 32'h0800002e; // B8 j 0xB8 (self), park here, done
		ROM[47] = 32'h00000020; // BC filler, this is the jump's delay slot, always executes once
	end

	// asynchronous / combinational read (word-addressed: pc_im/4)
	assign instruction_im = ROM[pc_im[31:2]];

endmodule