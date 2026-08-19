module mips (
	input  logic        clock_mips,
	input  logic        reset_mips,
	output logic [31:0] Writedata_mips,      // data to write into memory (sw)
	input  logic [31:0] Readdata_mips,       // data being read from memory (lw)
	output logic [31:0] address_mips,        // memory address to read/write
	output logic [31:0] pc_mips,             // instruction address to fetch
	input  logic [31:0] instruction_mips,    // instruction data to execute in the next cycle
	output logic        overflow_mips,       // flag for overflow (unused, see note below)
	output logic        invalid_mips,        // flag for invalid opcode (unused, see note below)
	output logic        memory_read_mips,
	output logic        memory_write_mips
);

	//---- Register file ----
	logic [31:0] Registers [0:31];

	initial begin
		for (int k = 0; k < 32; k++)
		Registers[k] = 32'h00000000;
		Registers[4] = 32'h00000004;
		Registers[5] = 32'h00000084;
		Registers[6] = 32'h0000008c;
		Registers[7] = 32'h00000001;
	end

	//---- Signal declarations ----
	// IF
	logic [31:0] IF_pc, IF_pc4, IF_pc_next;

	// IFID pipeline registers
	logic [31:0] IFID_pc4, IFID_instr;

	// ID
	logic [5:0]  ID_op;
	logic [15:0] ID_immed;
	logic [31:0] ID_instr, ID_extend, ID_rd1, ID_rd2, ID_pc4;
	logic [4:0]  ID_rs, ID_rt, ID_rd;
	logic        ID_RegDst, ID_RegWrite, ID_MemWrite, ID_MemRead, ID_ALUSrc, ID_MemtoReg;
	logic [1:0]  ID_ALUOp;
	logic        ID_Branch, ID_Jump, ID_BranchNE;
	logic [31:0] jumpaddress;
	logic        stall; // load-use hazard: freeze IF/ID, bubble IDEX
	logic        ID_UsesRt; // does the current ID instruction actually read rt as a source?

	// IDEX pipeline registers
	logic [31:0] IDEX_pc4, IDEX_rd1, IDEX_rd2, IDEX_extend;
	logic [4:0]  IDEX_rt, IDEX_rd, IDEX_rs;
	logic        IDEX_RegDst, IDEX_RegWrite, IDEX_MemWrite, IDEX_MemRead, IDEX_ALUSrc, IDEX_MemtoReg;
	logic [1:0]  IDEX_ALUOp;
	logic        IDEX_Branch, IDEX_BranchNE;

	// EX
	logic [31:0] alu1, alu2;
	logic [31:0] EX_ALUOut, EX_extend, EX_offset, EX_rd1, EX_rd2, EX_pc4, EX_btgt;
	logic [31:0] EX_rd1_fwd, EX_rd2_fwd;
	logic [5:0]  EX_funct;
	logic [3:0]  ALUctl;
	logic [1:0]  EX_ALUOp;
	logic        overflow, EX_Zero;
	logic [4:0]  EX_rs, EX_rt, EX_rd, EX_RegRd;
	logic [1:0]  ForwardA, ForwardB;
	logic        EX_RegDst, EX_RegWrite, EX_MemWrite, EX_MemRead, EX_ALUSrc, EX_MemtoReg;
	logic        EX_Branch, EX_BranchNE;

	// EXMEM pipeline registers
	logic [31:0] EXMEM_btgt, EXMEM_ALUOut, EXMEM_rd2;
	logic        EXMEM_Zero;
	logic [4:0]  EXMEM_RegRd;
	logic        EXMEM_RegWrite, EXMEM_MemWrite, EXMEM_MemRead, EXMEM_MemtoReg;
	logic        EXMEM_Branch, EXMEM_BranchNE;

	// MEM
	logic [31:0] MEM_memout, MEM_ALUOut, MEM_rd2, MEM_btgt;
	logic [4:0]  MEM_RegRd;
	logic        MEM_Zero, MEM_RegWrite, MEM_MemWrite, MEM_MemRead, MEM_MemtoReg;
	logic        MEM_Branch, MEM_BranchNE, MEM_PCSrc;

	// MEMWB pipeline registers
	logic [31:0] MEMWB_memout, MEMWB_ALUOut;
	logic [4:0]  MEMWB_RegRd;
	logic        MEMWB_RegWrite, MEMWB_MemtoReg;

	// WB
	logic [31:0] WB_memout, WB_wd, WB_ALUOut;
	logic [4:0]  WB_wn;
	logic        WB_MemtoReg, WB_RegWrite;

	//----------------------------------------------------
	// Inst memory & PC update (IF stage)
	//----------------------------------------------------

	always_ff @(posedge clock_mips or posedge reset_mips) begin
		if (reset_mips)
			IF_pc <= 32'h00000000;
		else if (stall)
			IF_pc <= IF_pc; // load-use hazard: hold PC, re-fetch same instruction
		else
			IF_pc <= IF_pc_next;
	end

	// next-state logic
	// jump wins immediately (resolved this cycle in ID, from the instruction currently in ID);
	// otherwise a branch resolved several cycles ago in MEM can redirect the PC;
	// otherwise just go sequential.
	assign IF_pc_next = ID_Jump    ? jumpaddress :
						 MEM_PCSrc ? MEM_btgt     :
						 IF_pc4;
	assign IF_pc4      = IF_pc + 32'd4;

	// output logic
	assign pc_mips = IF_pc;

	// **** SAVE TO PIPELINE REGISTERS
	// NOTE: reset added here (and on every pipeline register below) because
	// IF_pc_next now depends on ID_Jump/MEM_PCSrc, which trace back through
	// these registers. Without a defined reset value, they start unknown in
	// simulation (and undefined on real hardware) until real instructions
	// have flowed all the way through the pipeline, corrupting the very
	// first PC-select decision. The original branch-free version never
	// needed this, since IF_pc_next was always just IF_pc4, independent of
	// every other pipeline register.
	always_ff @(posedge clock_mips or posedge reset_mips) begin
		if (reset_mips) begin
			IFID_pc4   <= 32'h0;
			IFID_instr <= 32'h0;
		end else if (stall) begin
			IFID_pc4   <= IFID_pc4;   // load-use hazard: hold, re-decode same instruction
			IFID_instr <= IFID_instr;
		end else begin
			IFID_pc4   <= IF_pc4;            //1
			IFID_instr <= instruction_mips;  //2
		end
	end

	//----------------------------------------------------
	// inst analysis (ID stage)
	//----------------------------------------------------

	// **RETRIEVE FROM PIPELINE REGISTERS
	assign ID_pc4   = IFID_pc4;   // needed for jump target computation
	assign ID_instr = IFID_instr; //3

	assign ID_op = ID_instr[31:26]; //4
	assign ID_rs = ID_instr[25:21]; //5
	assign ID_rt = ID_instr[20:16]; //6
	assign ID_rd = ID_instr[15:11]; //7
	// sign extend
	assign ID_immed  = ID_instr[15:0];              //8
	assign ID_extend = {{16{ID_immed[15]}}, ID_immed}; //9

	// control signals
	always_comb begin
		ID_RegDst   = 1'b0;  //10
		ID_RegWrite = 1'b0;  //11
		ID_MemWrite = 1'b0;  //12
		ID_MemRead  = 1'b0;  //13
		ID_ALUSrc   = 1'b0;  //14
		ID_MemtoReg = 1'b0;  //15
		ID_ALUOp    = 2'b00; //16
		ID_Branch   = 1'b0;
		ID_Jump     = 1'b0;

		if (ID_op == 6'b000000) begin
			ID_RegDst   = 1'b1;
			ID_RegWrite = 1'b1;
			ID_ALUOp    = 2'b10;
		end else if (ID_op == 6'b100011) begin
			ID_RegWrite = 1'b1;
			ID_MemRead  = 1'b1;
			ID_ALUSrc   = 1'b1;
			ID_MemtoReg = 1'b1;
		end else if (ID_op == 6'b101011) begin
			ID_MemWrite = 1'b1;
			ID_ALUSrc   = 1'b1;
		end else if (ID_op == 6'b000100 || ID_op == 6'b000101) begin // beq / bne
			ID_Branch = 1'b1;
			ID_ALUOp  = 2'b01; // tells EX stage: force subtract
		end else if (ID_op == 6'b000010) begin // j
			ID_Jump = 1'b1;
		end
	end

	// beq vs bne share the same "Branch" flag; this bit says which comparison
	// (op[0]=0 -> beq/branch-if-equal, op[0]=1 -> bne/branch-if-not-equal)
	assign ID_BranchNE = ID_op[0];

	// jump target = upper 4 bits of PC+4, concatenated with the 26-bit
	// instruction field, shifted left 2 for word alignment
	assign jumpaddress = {ID_pc4[31:28], ID_instr[25:0], 2'b00};

	assign ID_rd1 = Registers[ID_rs]; //17
	assign ID_rd2 = Registers[ID_rt]; //18

	// load-use hazard detection: the instruction currently sitting in IDEX
	// (about to enter EX) is a load, and this cycle's ID instruction reads
	// the register it's about to write. Forwarding can't fix this, the
	// loaded value isn't available until MEM completes, so stall one cycle.
	//
	// ID_rt is only a real source register for R-type, sw, and beq/bne -
	// for lw, the rt field is that instruction's own destination, not
	// something it reads, so it must be excluded here. Without this
	// exclusion, two back-to-back loads into the same register falsely
	// trigger a stall even though the second load never reads that
	// register, only writes it.
	assign ID_UsesRt = !(ID_op == 6'b100011); // false only for lw
	assign stall = IDEX_MemRead &&
				   ((IDEX_rt == ID_rs) || (ID_UsesRt && (IDEX_rt == ID_rt))) &&
				   (IDEX_rt != 5'h0);

	// **** SAVE TO PIPELINE REGISTERS
	always_ff @(posedge clock_mips or posedge reset_mips) begin
		if (reset_mips) begin
			IDEX_rd1      <= 32'h0;
			IDEX_rd2      <= 32'h0;
			IDEX_extend   <= 32'h0;
			IDEX_rs       <= 5'h0;
			IDEX_rt       <= 5'h0;
			IDEX_rd       <= 5'h0;
			IDEX_RegDst   <= 1'b0;
			IDEX_RegWrite <= 1'b0;
			IDEX_MemWrite <= 1'b0;
			IDEX_MemRead  <= 1'b0;
			IDEX_ALUSrc   <= 1'b0;
			IDEX_MemtoReg <= 1'b0;
			IDEX_ALUOp    <= 2'b00;
			IDEX_pc4      <= 32'h0;
			IDEX_Branch   <= 1'b0;
			IDEX_BranchNE <= 1'b0;
		end else if (stall) begin
			// insert a bubble: the hazard instruction stays in ID (IFID is
			// frozen too, above) and gets re-decoded next cycle once the
			// load has moved on, only the control signals need zeroing,
			// since a bubble must not write any register or memory.
			IDEX_RegWrite <= 1'b0;
			IDEX_MemWrite <= 1'b0;
			IDEX_MemRead  <= 1'b0;
			IDEX_Branch   <= 1'b0;
		end else begin
			IDEX_rd1      <= ID_rd1;      //19
			IDEX_rd2      <= ID_rd2;      //20
			IDEX_extend   <= ID_extend;   //21
			IDEX_rs       <= ID_rs;
			IDEX_rt       <= ID_rt;       //22
			IDEX_rd       <= ID_rd;       //23
			IDEX_RegDst   <= ID_RegDst;   //24
			IDEX_RegWrite <= ID_RegWrite; //25
			IDEX_MemWrite <= ID_MemWrite; //26
			IDEX_MemRead  <= ID_MemRead;  //27
			IDEX_ALUSrc   <= ID_ALUSrc;   //28
			IDEX_MemtoReg <= ID_MemtoReg; //29
			IDEX_ALUOp    <= ID_ALUOp;    //30
			IDEX_pc4      <= ID_pc4;
			IDEX_Branch   <= ID_Branch;
			IDEX_BranchNE <= ID_BranchNE;
		end
	end

	//----------------------------------------------------
	// ALU interfacing (EX stage)
	//----------------------------------------------------

	// **RETRIEVE FROM PIPELINE REGISTERS
	assign EX_rd1      = IDEX_rd1;      //31
	assign EX_rd2       = IDEX_rd2;      //32
	assign EX_rs        = IDEX_rs;
	assign EX_rt        = IDEX_rt;       //33
	assign EX_rd        = IDEX_rd;       //34
	assign EX_extend    = IDEX_extend;   //35
	assign EX_RegDst    = IDEX_RegDst;   //36
	assign EX_ALUSrc    = IDEX_ALUSrc;   //37
	assign EX_ALUOp     = IDEX_ALUOp;    //38
	assign EX_RegWrite  = IDEX_RegWrite; //39
	assign EX_MemWrite  = IDEX_MemWrite; //40
	assign EX_MemRead   = IDEX_MemRead;  //41
	assign EX_MemtoReg  = IDEX_MemtoReg; //42
	assign EX_pc4        = IDEX_pc4;
	assign EX_Branch     = IDEX_Branch;
	assign EX_BranchNE   = IDEX_BranchNE;

	assign EX_funct = EX_extend[5:0]; //43

	// Forwarding unit: does an instruction ahead in the pipeline (currently
	// in MEM, or currently in WB) hold the value this instruction needs?
	// EX/MEM has priority over MEM/WB, since it's the more recent result.
	// A load's own EX/MEM entry never matches here, by the time it would,
	// the stall above has already turned it into a harmless bubble, so
	// this path only ever forwards real ALU results, never a load's
	// in-flight memory address.
	always_comb begin
		if (EXMEM_RegWrite && (EXMEM_RegRd != 5'h0) && (EXMEM_RegRd == EX_rs))
			ForwardA = 2'b10;
		else if (MEMWB_RegWrite && (MEMWB_RegRd != 5'h0) && (MEMWB_RegRd == EX_rs))
			ForwardA = 2'b01;
		else
			ForwardA = 2'b00;

		if (EXMEM_RegWrite && (EXMEM_RegRd != 5'h0) && (EXMEM_RegRd == EX_rt))
			ForwardB = 2'b10;
		else if (MEMWB_RegWrite && (MEMWB_RegRd != 5'h0) && (MEMWB_RegRd == EX_rt))
			ForwardB = 2'b01;
		else
			ForwardB = 2'b00;
	end

	assign EX_rd1_fwd = (ForwardA == 2'b10) ? EXMEM_ALUOut :
						 (ForwardA == 2'b01) ? WB_wd        : EX_rd1;
	assign EX_rd2_fwd = (ForwardB == 2'b10) ? EXMEM_ALUOut :
						 (ForwardB == 2'b01) ? WB_wd        : EX_rd2;

	assign alu1 = EX_rd1_fwd;             //44
	assign alu2 = EX_ALUSrc ? EX_extend : EX_rd2_fwd; //45

	always_comb begin
		ALUctl = 4'b0010; //46 (default: add, used for lw/sw address calc)
		case (EX_ALUOp)
			2'b01: ALUctl = 4'b0110; // beq/bne: force subtract, so Zero tells us rs==rt
			2'b10: begin             // R-type: decode from funct field
				case (EX_funct)
					6'b100000: ALUctl = 4'b0010; // add
					6'b100010: ALUctl = 4'b0110; // sub
					6'b100100: ALUctl = 4'b0000; // and
					6'b100101: ALUctl = 4'b0001; // or
					6'b101010: ALUctl = 4'b0111; // slt
					default:   ALUctl = 4'b0010;
				endcase
			end
			default: ALUctl = 4'b0010; // 00: add (lw/sw)
		endcase
	end

	assign EX_RegRd = EX_RegDst ? EX_rd : EX_rt; //47

	// branch target: PC+4 plus the sign-extended, word-aligned immediate offset
	assign EX_offset = {EX_extend[29:0], 2'b00}; // EX_extend << 2
	assign EX_btgt    = EX_pc4 + EX_offset;

	// The component ALU_32 produces (ALUresult, overflow, Zero)
	//---- Component instantiation ----
	ALU_32 ALU_32_1 (
		.A_alu32        (alu1),
		.B_alu32        (alu2),
		.ALUctl_alu32   (ALUctl),
		.ALUresult_alu32(EX_ALUOut),
		.overflow_alu32 (overflow),
		.Zero_alu32     (EX_Zero)
	);

	// **** SAVE TO PIPELINE REGISTERS
	always_ff @(posedge clock_mips or posedge reset_mips) begin
		if (reset_mips) begin
			EXMEM_ALUOut   <= 32'h0;
			EXMEM_rd2      <= 32'h0;
			EXMEM_RegRd    <= 5'h0;
			EXMEM_RegWrite <= 1'b0;
			EXMEM_MemWrite <= 1'b0;
			EXMEM_MemRead  <= 1'b0;
			EXMEM_MemtoReg <= 1'b0;
			EXMEM_btgt     <= 32'h0;
			EXMEM_Zero     <= 1'b0;
			EXMEM_Branch   <= 1'b0;
			EXMEM_BranchNE <= 1'b0;
		end else begin
			EXMEM_ALUOut   <= EX_ALUOut;   //48
			EXMEM_rd2      <= EX_rd2_fwd;  //49 (forwarded, so sw stores correct data)
			EXMEM_RegRd    <= EX_RegRd;    //50
			EXMEM_RegWrite <= EX_RegWrite; //51
			EXMEM_MemWrite <= EX_MemWrite; //52
			EXMEM_MemRead  <= EX_MemRead;  //53
			EXMEM_MemtoReg <= EX_MemtoReg; //54
			EXMEM_btgt     <= EX_btgt;
			EXMEM_Zero     <= EX_Zero;
			EXMEM_Branch   <= EX_Branch;
			EXMEM_BranchNE <= EX_BranchNE;
		end
	end

	//----------------------------------------------------
	// Memory interfacing (MEM stage)
	//----------------------------------------------------

	// **RETRIEVE FROM PIPELINE REGISTERS
	assign MEM_ALUOut   = EXMEM_ALUOut;
	assign MEM_rd2       = EXMEM_rd2;
	assign MEM_RegRd     = EXMEM_RegRd;
	assign MEM_RegWrite  = EXMEM_RegWrite; //58
	assign MEM_MemWrite  = EXMEM_MemWrite; //59
	assign MEM_MemRead   = EXMEM_MemRead;  //60
	assign MEM_MemtoReg  = EXMEM_MemtoReg; //61
	assign MEM_btgt       = EXMEM_btgt;
	assign MEM_Zero       = EXMEM_Zero;
	assign MEM_Branch     = EXMEM_Branch;
	assign MEM_BranchNE   = EXMEM_BranchNE;

	// beq: taken when Zero=1 (BranchNE=0) -> Zero ^ 0 = Zero
	// bne: taken when Zero=0 (BranchNE=1) -> Zero ^ 1 = ~Zero
	assign MEM_PCSrc = MEM_Branch & (MEM_Zero ^ MEM_BranchNE);

	assign Writedata_mips    = MEM_rd2;       //62
	assign address_mips      = MEM_ALUOut;    //63
	assign memory_write_mips = MEM_MemWrite;  //64
	assign memory_read_mips  = MEM_MemRead;   //65
	assign MEM_memout        = Readdata_mips; //66

	// **** SAVE TO PIPELINE REGISTERS
	always_ff @(posedge clock_mips or posedge reset_mips) begin
		if (reset_mips) begin
			MEMWB_memout   <= 32'h0;
			MEMWB_ALUOut   <= 32'h0;
			MEMWB_RegRd    <= 5'h0;
			MEMWB_RegWrite <= 1'b0;
			MEMWB_MemtoReg <= 1'b0;
		end else begin
			MEMWB_memout   <= MEM_memout;   //67
			MEMWB_ALUOut   <= MEM_ALUOut;   //68
			MEMWB_RegRd    <= MEM_RegRd;    //69
			MEMWB_RegWrite <= MEM_RegWrite; //70
			MEMWB_MemtoReg <= MEM_MemtoReg; //71
		end
	end

	//----------------------------------------------------
	// synchronous write to registers (WB stage)
	//----------------------------------------------------

	// **RETRIEVE FROM PIPELINE REGISTERS
	assign WB_memout   = MEMWB_memout;   //72
	assign WB_ALUOut   = MEMWB_ALUOut;   //73
	assign WB_wn        = MEMWB_RegRd;    //74
	assign WB_RegWrite  = MEMWB_RegWrite; //75
	assign WB_MemtoReg  = MEMWB_MemtoReg; //76

	assign WB_wd = WB_MemtoReg ? WB_memout : WB_ALUOut; //77

	always_ff @(negedge clock_mips) begin
		if (WB_RegWrite)
			Registers[WB_wn] <= WB_wd;
	end

	// NOTE: overflow_mips and invalid_mips are declared as outputs in the
	// entity but are not driven anywhere in the architecture, a
	// pre-existing gap carried over faithfully from the original VHDL
	// rather than silently patched. Worth wiring these up when the ISA is
	// extended (overflow especially, once more arithmetic is added).

endmodule