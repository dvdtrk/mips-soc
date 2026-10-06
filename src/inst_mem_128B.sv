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

	logic [31:0] ROM [0:238];

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
		ROM[98] = 32'h218c0140; // 188 addi $12, $12, 320, move cursor to row 2 -
		                        //    leaves "hello world" on row 1 untouched
		ROM[99] = 32'h20167fff; // 18c addi $22, $0, 32767, building the key-event
		                        //    interface's base address, 0x70010
		ROM[100] = 32'h22d67fff; // 190 addi $22, $22, 32767
		ROM[101] = 32'h22d67fff; // 194 addi $22, $22, 32767
		ROM[102] = 32'h22d67fff; // 198 addi $22, $22, 32767
		ROM[103] = 32'h22d67fff; // 19c addi $22, $22, 32767
		ROM[104] = 32'h22d67fff; // 1a0 addi $22, $22, 32767
		ROM[105] = 32'h22d67fff; // 1a4 addi $22, $22, 32767
		ROM[106] = 32'h22d67fff; // 1a8 addi $22, $22, 32767
		ROM[107] = 32'h22d67fff; // 1ac addi $22, $22, 32767
		ROM[108] = 32'h22d67fff; // 1b0 addi $22, $22, 32767
		ROM[109] = 32'h22d67fff; // 1b4 addi $22, $22, 32767
		ROM[110] = 32'h22d67fff; // 1b8 addi $22, $22, 32767
		ROM[111] = 32'h22d67fff; // 1bc addi $22, $22, 32767
		ROM[112] = 32'h22d67fff; // 1c0 addi $22, $22, 32767
		ROM[113] = 32'h22d6001e; // 1c4 addi $22, $22, 30, $22 now holds 0x70010,
		                         //    the key-event data address
		// POLL loop starts here (0x1c8): check for a key, and only act
		// once one is actually ready

		ROM[114] = 32'h20147fff; // 1c8 addi $20, $0, 32767, building the cursor
		                         //    position register's address, 0x70020
		ROM[115] = 32'h22947fff; // 1cc addi $20, $20, 32767
		ROM[116] = 32'h22947fff; // 1d0 addi $20, $20, 32767
		ROM[117] = 32'h22947fff; // 1d4 addi $20, $20, 32767
		ROM[118] = 32'h22947fff; // 1d8 addi $20, $20, 32767
		ROM[119] = 32'h22947fff; // 1dc addi $20, $20, 32767
		ROM[120] = 32'h22947fff; // 1e0 addi $20, $20, 32767
		ROM[121] = 32'h22947fff; // 1e4 addi $20, $20, 32767
		ROM[122] = 32'h22947fff; // 1e8 addi $20, $20, 32767
		ROM[123] = 32'h22947fff; // 1ec addi $20, $20, 32767
		ROM[124] = 32'h22947fff; // 1f0 addi $20, $20, 32767
		ROM[125] = 32'h22947fff; // 1f4 addi $20, $20, 32767
		ROM[126] = 32'h22947fff; // 1f8 addi $20, $20, 32767
		ROM[127] = 32'h22947fff; // 1fc addi $20, $20, 32767
		ROM[128] = 32'h2294002e; // 200 addi $20, $20, 46, $20 now holds 0x70020
		ROM[129] = 32'hae8c0000; // 204 sw $12, 0($20), show the cursor at the
		                         //    starting position right away, before
		                         //    any character has been typed


		// SDRAM test from the CPU ------------------------------------------------------------
		// Writes four values to SDRAM through ordinary sw instructions (two
		// neighbors, a second bank, and the last word of the chip), reads them
		// back with lw, and compares. LED register: 1 = running, 3 = passed,
		// 5 = failed. Also prints P or F at the end of the "hello world" line.
		ROM[130] = 32'h20010001; // 208 addi $1, $0, 1, LED code 1 = SDRAM test running
		ROM[131] = 32'haec10020; // 20c sw $1, 32($22), LED register at 0x70030 (0x70010 + 0x20)
		ROM[132] = 32'h20120001; // 210 addi $18, $0, 1, start doubling
		ROM[133] = 32'h02529020; // 214 add $18, $18, $18, x2
		ROM[134] = 32'h02529020; // 218 add $18, $18, $18
		ROM[135] = 32'h02529020; // 21c add $18, $18, $18
		ROM[136] = 32'h02529020; // 220 add $18, $18, $18
		ROM[137] = 32'h02529020; // 224 add $18, $18, $18
		ROM[138] = 32'h02529020; // 228 add $18, $18, $18
		ROM[139] = 32'h02529020; // 22c add $18, $18, $18
		ROM[140] = 32'h02529020; // 230 add $18, $18, $18
		ROM[141] = 32'h02529020; // 234 add $18, $18, $18
		ROM[142] = 32'h02529020; // 238 add $18, $18, $18
		ROM[143] = 32'h02529020; // 23c add $18, $18, $18
		ROM[144] = 32'h02529020; // 240 add $18, $18, $18
		ROM[145] = 32'h02529020; // 244 add $18, $18, $18
		ROM[146] = 32'h02529020; // 248 add $18, $18, $18
		ROM[147] = 32'h02529020; // 24c add $18, $18, $18
		ROM[148] = 32'h02529020; // 250 add $18, $18, $18
		ROM[149] = 32'h02529020; // 254 add $18, $18, $18
		ROM[150] = 32'h02529020; // 258 add $18, $18, $18
		ROM[151] = 32'h02529020; // 25c add $18, $18, $18
		ROM[152] = 32'h02529020; // 260 add $18, $18, $18
		ROM[153] = 32'h02529020; // 264 add $18, $18, $18
		ROM[154] = 32'h02529020; // 268 add $18, $18, $18
		ROM[155] = 32'h02529020; // 26c add $18, $18, $18
		ROM[156] = 32'h02529020; // 270 add $18, $18, $18
		ROM[157] = 32'h02528020; // 274 add $16, $18, $18, 2^25
		ROM[158] = 32'h02108020; // 278 add $16, $16, $16, $16 = 0x04000000, SDRAM base
		ROM[159] = 32'h02129820; // 27c add $19, $16, $18, $19 = 0x05000000, bank 1
		ROM[160] = 32'h02107820; // 280 add $15, $16, $16, 0x08000000
		ROM[161] = 32'h21effffc; // 284 addi $15, $15, -4, $15 = 0x07FFFFFC, the last word of the SDRAM
		ROM[162] = 32'h20027fff; // 288 addi $2, $0, 32767
		ROM[163] = 32'h00421020; // 28c add $2, $2, $2, x2
		ROM[164] = 32'h00421020; // 290 add $2, $2, $2
		ROM[165] = 32'h00421020; // 294 add $2, $2, $2
		ROM[166] = 32'h00421020; // 298 add $2, $2, $2
		ROM[167] = 32'h00421020; // 29c add $2, $2, $2
		ROM[168] = 32'h00421020; // 2a0 add $2, $2, $2
		ROM[169] = 32'h00421020; // 2a4 add $2, $2, $2
		ROM[170] = 32'h00421020; // 2a8 add $2, $2, $2
		ROM[171] = 32'h00421020; // 2ac add $2, $2, $2
		ROM[172] = 32'h00421020; // 2b0 add $2, $2, $2
		ROM[173] = 32'h00421020; // 2b4 add $2, $2, $2
		ROM[174] = 32'h00421020; // 2b8 add $2, $2, $2
		ROM[175] = 32'h00421020; // 2bc add $2, $2, $2
		ROM[176] = 32'h00421020; // 2c0 add $2, $2, $2
		ROM[177] = 32'h00421020; // 2c4 add $2, $2, $2
		ROM[178] = 32'h00421020; // 2c8 add $2, $2, $2
		ROM[179] = 32'h00421020; // 2cc add $2, $2, $2
		ROM[180] = 32'h20425a5a; // 2d0 addi $2, $2, 23130, $2 = 0xFFFE5A5A
		ROM[181] = 32'h00421820; // 2d4 add $3, $2, $2, $3 = second value
		ROM[182] = 32'h00632020; // 2d8 add $4, $3, $3, $4 = third value
		ROM[183] = 32'h00832820; // 2dc add $5, $4, $3, $5 = fourth value
		ROM[184] = 32'hae020000; // 2e0 sw $2, 0($16), bank 0, word 0
		ROM[185] = 32'hae030004; // 2e4 sw $3, 4($16), bank 0, the NEXT word (neighbor)
		ROM[186] = 32'hae640000; // 2e8 sw $4, 0($19), bank 1
		ROM[187] = 32'hade50000; // 2ec sw $5, 0($15), last word of the chip
		ROM[188] = 32'h8e060000; // 2f0 lw $6, 0($16)
		ROM[189] = 32'h8e070004; // 2f4 lw $7, 4($16)
		ROM[190] = 32'h8e6a0000; // 2f8 lw $10, 0($19)
		ROM[191] = 32'h8deb0000; // 2fc lw $11, 0($15)
		ROM[192] = 32'h00c20822; // 300 sub $1, $6, $2
		ROM[193] = 32'h00e37022; // 304 sub $14, $7, $3
		ROM[194] = 32'h0144a822; // 308 sub $21, $10, $4
		ROM[195] = 32'h0165b822; // 30c sub $23, $11, $5
		ROM[196] = 32'h002e0825; // 310 or  $1, $1, $14
		ROM[197] = 32'h00350825; // 314 or  $1, $1, $21
		ROM[198] = 32'h00370825; // 318 or  $1, $1, $23, $1 == 0 only if all four matched
		ROM[199] = 32'h1020000a; // 31c beq $1, $0, PASS (offset 10)
		ROM[200] = 32'h00000020; // 320 nop (delay slot 1 of 3)
		ROM[201] = 32'h00000020; // 324 nop (delay slot 2 of 3)
		ROM[202] = 32'h00000020; // 328 nop (delay slot 3 of 3)
		ROM[203] = 32'h20010005; // 32c addi $1, $0, 5, LED code 5 = failed
		ROM[204] = 32'haec10020; // 330 sw $1, 32($22)
		ROM[205] = 32'h20010046; // 334 addi $1, $0, 70, 'F'
		ROM[206] = 32'h218efef0; // 338 addi $14, $12, -272, text buffer row 0, column 12
		ROM[207] = 32'hadc10000; // 33c sw $1, 0($14), show F on the screen
		ROM[208] = 32'h080000d7; // 340 j DONE (word 215)
		ROM[209] = 32'h00000020; // 344 nop (jump delay slot)
		ROM[210] = 32'h20010003; // 348 addi $1, $0, 3, LED code 3 = passed
		ROM[211] = 32'haec10020; // 34c sw $1, 32($22)
		ROM[212] = 32'h20010050; // 350 addi $1, $0, 80, 'P'
		ROM[213] = 32'h218efef0; // 354 addi $14, $12, -272, text buffer row 0, column 12
		ROM[214] = 32'hadc10000; // 358 sw $1, 0($14), show P on the screen
		// ----------------------------------------------------------------------------------


		// POLL loop starts here (0x208)
		ROM[215] = 32'h8ed80004; // 208 lw $24, 4($22), read status
		ROM[216] = 32'h1300fffe; // 20c beq $24, $0, POLL, no new key yet, loop back
		ROM[217] = 32'h00000020; // 210 nop (delay slot 1 of 3)
		ROM[218] = 32'h00000020; // 214 nop (delay slot 2 of 3)
		ROM[219] = 32'h00000020; // 218 nop (delay slot 3 of 3)
		ROM[220] = 32'h8ed90000; // 21c lw $25, 0($22), read the character
		ROM[221] = 32'h201a0008; // 220 addi $26, $0, 8, the ASCII backspace value
		ROM[222] = 32'h133a0009; // 224 beq $25, $26, BACKSPACE, is this a
		                         //    backspace instead of a normal character?
		ROM[223] = 32'h00000020; // 228 nop (delay slot 1 of 3)
		ROM[224] = 32'h00000020; // 22c nop (delay slot 2 of 3)
		ROM[225] = 32'h00000020; // 230 nop (delay slot 3 of 3)
		// normal path: write the character and advance
		ROM[226] = 32'had990000; // 234 sw $25, 0($12), write the character into
		                         //    the text buffer at the current cursor
		ROM[227] = 32'h218c0004; // 238 addi $12, $12, 4, advance the cursor
		ROM[228] = 32'hae8c0000; // 23c sw $12, 0($20), update the cursor
		                         //    position register so the hardware
		                         //    cursor indicator moves with it
		ROM[229] = 32'haec00008; // 240 sw $0, 8($22), acknowledge
		ROM[230] = 32'h080000d7; // 244 j POLL, loop back and keep polling
		ROM[231] = 32'h00000020; // 248 nop, the jump's delay slot
		// BACKSPACE handler (0x24c): move the cursor back one cell and
		// erase whatever character was there by overwriting it with a
		// space, rather than actually storing a backspace character
		ROM[232] = 32'h218cfffc; // 24c addi $12, $12, -4, move cursor back
		ROM[233] = 32'h201b0020; // 250 addi $27, $0, 32, a space character
		ROM[234] = 32'had9b0000; // 254 sw $27, 0($12), erase the character
		                         //    that was there
		ROM[235] = 32'hae8c0000; // 258 sw $12, 0($20), update the cursor
		                         //    position register to match
		ROM[236] = 32'haec00008; // 25c sw $0, 8($22), acknowledge
		ROM[237] = 32'h080000d7; // 260 j POLL, loop back and keep polling
		ROM[238] = 32'h00000020; // 264 nop, the jump's delay slot
	end 
	
	// asynchronous / combinational read (word-addressed: pc_im/4)
	assign instruction_im = ROM[pc_im[31:2]];

endmodule