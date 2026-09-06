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

	logic [31:0] ROM [0:99];

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
		ROM[46] = 32'h20087fff; // b8 addi $8, $0, 32767, building the center pixel address
		ROM[47] = 32'h21087fff; // bc addi $8, $8, 32767
		ROM[48] = 32'h21087fff; // c0 addi $8, $8, 32767
		ROM[49] = 32'h21087fff; // c4 addi $8, $8, 32767
		ROM[50] = 32'h21087fff; // c8 addi $8, $8, 32767
		ROM[51] = 32'h21087fff; // cc addi $8, $8, 32767
		ROM[52] = 32'h21085a86; // d0 addi $8, $8, 23174, $8 now holds 0x35a80,
		                        //    the center pixel address in the resized 320x240 framebuffer
		ROM[53] = 32'h200900e0; // d4 addi $9, $0, 224, a bright color value
		ROM[54] = 32'had090000; // d8 sw $9, 0($8), draw the center pixel
		ROM[55] = 32'h210afb00; // dc addi $10, $8, -1280, one row up (320 words per row)
		ROM[56] = 32'had490000; // e0 sw $9, 0($10)
		ROM[57] = 32'h210a0500; // e4 addi $10, $8, 1280, one row down
		ROM[58] = 32'had490000; // e8 sw $9, 0($10)
		ROM[59] = 32'h210afffc; // ec addi $10, $8, -4, one pixel left
		ROM[60] = 32'had490000; // f0 sw $9, 0($10)
		ROM[61] = 32'h210a0004; // f4 addi $10, $8, 4, one pixel right
		ROM[62] = 32'had490000; // f8 sw $9, 0($10)
		ROM[63] = 32'h200c7fff; // fc addi $12, $0, 32767, building the text buffer's base
		                        //    address, 0x60000, kept clear of the framebuffer's real
		                        //    range (which extends to 0x5b000) after a bug where the
		                        //    two overlapped and every text write also corrupted a
		                        //    nearby framebuffer pixel
		ROM[64] = 32'h218c7fff; // 100 addi $12, $12, 32767
		ROM[65] = 32'h218c7fff; // 104 addi $12, $12, 32767
		ROM[66] = 32'h218c7fff; // 108 addi $12, $12, 32767
		ROM[67] = 32'h218c7fff; // 10c addi $12, $12, 32767
		ROM[68] = 32'h218c7fff; // 110 addi $12, $12, 32767
		ROM[69] = 32'h218c7fff; // 114 addi $12, $12, 32767
		ROM[70] = 32'h218c7fff; // 118 addi $12, $12, 32767
		ROM[71] = 32'h218c7fff; // 11c addi $12, $12, 32767
		ROM[72] = 32'h218c7fff; // 120 addi $12, $12, 32767
		ROM[73] = 32'h218c7fff; // 124 addi $12, $12, 32767
		ROM[74] = 32'h218c7fff; // 128 addi $12, $12, 32767
		ROM[75] = 32'h218c000c; // 12c addi $12, $12, 12, $12 now holds 0x60000
		ROM[76] = 32'h200d0068; // 130 addi $13, $0, 104, 'h'
		ROM[77] = 32'had8d0000; // 134 sw $13, 0($12), write 'h' at column 0
		ROM[78] = 32'h200d0065; // 138 addi $13, $0, 101, 'e'
		ROM[79] = 32'had8d0004; // 13c sw $13, 4($12), write 'e' at column 1
		ROM[80] = 32'h200d006c; // 140 addi $13, $0, 108, 'l'
		ROM[81] = 32'had8d0008; // 144 sw $13, 8($12), write 'l' at column 2
		ROM[82] = 32'h200d006c; // 148 addi $13, $0, 108, 'l'
		ROM[83] = 32'had8d000c; // 14c sw $13, 12($12), write 'l' at column 3
		ROM[84] = 32'h200d006f; // 150 addi $13, $0, 111, 'o'
		ROM[85] = 32'had8d0010; // 154 sw $13, 16($12), write 'o' at column 4
		ROM[86] = 32'h200d0020; // 158 addi $13, $0, 32, space
		ROM[87] = 32'had8d0014; // 15c sw $13, 20($12), write space at column 5
		ROM[88] = 32'h200d0077; // 160 addi $13, $0, 119, 'w'
		ROM[89] = 32'had8d0018; // 164 sw $13, 24($12), write 'w' at column 6
		ROM[90] = 32'h200d006f; // 168 addi $13, $0, 111, 'o'
		ROM[91] = 32'had8d001c; // 16c sw $13, 28($12), write 'o' at column 7
		ROM[92] = 32'h200d0072; // 170 addi $13, $0, 114, 'r'
		ROM[93] = 32'had8d0020; // 174 sw $13, 32($12), write 'r' at column 8
		ROM[94] = 32'h200d006c; // 178 addi $13, $0, 108, 'l'
		ROM[95] = 32'had8d0024; // 17c sw $13, 36($12), write 'l' at column 9
		ROM[96] = 32'h200d0064; // 180 addi $13, $0, 100, 'd'
		ROM[97] = 32'had8d0028; // 184 sw $13, 40($12), write 'd' at column 10
		ROM[98] = 32'h08000062; // 188 j 0x188 (self), park here, done
		ROM[99] = 32'h00000020; // 18c filler, the jump's delay slot, always executes
	// asynchronous / combinational read (word-addressed: pc_im/4)
	end 

	assign instruction_im = ROM[pc_im[31:2]];

endmodule