module mips (
    input  logic        clock_mips,
    input  logic        reset_mips,
    output logic [31:0] Writedata_mips,      // data to write into memory (sw)
    input  logic [31:0] Readdata_mips,       // data being read from memory (lw)
    output logic [31:0] address_mips,        // memory address to read/write
    output logic [31:0] pc_mips,             // instruction address to fetch
    input  logic [31:0] instruction_mips,    // instruction data to execute in the next cycle
    output logic        overflow_mips,       // flag for overflow (unused - see note below)
    output logic        invalid_mips,        // flag for invalid opcode (unused - see note below)
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

    // IDEX pipeline registers
    logic [31:0] IDEX_pc4, IDEX_rd1, IDEX_rd2, IDEX_extend;
    logic [4:0]  IDEX_rt, IDEX_rd;
    logic        IDEX_RegDst, IDEX_RegWrite, IDEX_MemWrite, IDEX_MemRead, IDEX_ALUSrc, IDEX_MemtoReg;
    logic [1:0]  IDEX_ALUOp;

    // EX
    logic [31:0] alu1, alu2;
    logic [31:0] EX_ALUOut, EX_extend, EX_offset, EX_rd1, EX_rd2, EX_pc4;
    logic [5:0]  EX_funct;
    logic [3:0]  ALUctl;
    logic [1:0]  EX_ALUOp;
    logic        overflow, EX_Zero;
    logic [4:0]  EX_rt, EX_rd, EX_RegRd;
    logic        EX_RegDst, EX_RegWrite, EX_MemWrite, EX_MemRead, EX_ALUSrc, EX_MemtoReg;

    // EXMEM pipeline registers
    logic [31:0] EXMEM_btgt, EXMEM_ALUOut, EXMEM_rd2;
    logic        EXMEM_Zero;
    logic [4:0]  EXMEM_RegRd;
    logic        EXMEM_RegWrite, EXMEM_MemWrite, EXMEM_MemRead, EXMEM_MemtoReg;

    // MEM
    logic [31:0] MEM_memout, MEM_ALUOut, MEM_rd2;
    logic [4:0]  MEM_RegRd;
    logic        MEM_Zero, MEM_RegWrite, MEM_MemWrite, MEM_MemRead, MEM_MemtoReg;

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
        else
            IF_pc <= IF_pc_next;
    end

    // next-state logic
    assign IF_pc_next = IF_pc4;
    assign IF_pc4      = IF_pc + 32'd4;

    // output logic
    assign pc_mips = IF_pc;

    // **** SAVE TO PIPELINE REGISTERS
    always_ff @(posedge clock_mips) begin
        IFID_pc4   <= IF_pc4;            //1
        IFID_instr <= instruction_mips;  //2
    end

    //----------------------------------------------------
    // inst analysis (ID stage)
    //----------------------------------------------------

    // **RETRIEVE FROM PIPELINE REGISTERS
    assign ID_instr = IFID_instr; //3

    // ---- your code (ID stage) ----
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
        end
    end

    assign ID_rd1 = Registers[ID_rs]; //17
    assign ID_rd2 = Registers[ID_rt]; //18

    // **** SAVE TO PIPELINE REGISTERS
    always_ff @(posedge clock_mips) begin
        IDEX_rd1      <= ID_rd1;      //19
        IDEX_rd2      <= ID_rd2;      //20
        IDEX_extend   <= ID_extend;   //21
        IDEX_rt       <= ID_rt;       //22
        IDEX_rd       <= ID_rd;       //23
        IDEX_RegDst   <= ID_RegDst;   //24
        IDEX_RegWrite <= ID_RegWrite; //25
        IDEX_MemWrite <= ID_MemWrite; //26
        IDEX_MemRead  <= ID_MemRead;  //27
        IDEX_ALUSrc   <= ID_ALUSrc;   //28
        IDEX_MemtoReg <= ID_MemtoReg; //29
        IDEX_ALUOp    <= ID_ALUOp;    //30
    end

    //----------------------------------------------------
    // ALU interfacing (EX stage)
    //----------------------------------------------------

    // **RETRIEVE FROM PIPELINE REGISTERS
    assign EX_rd1      = IDEX_rd1;      //31
    assign EX_rd2       = IDEX_rd2;      //32
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

    // ---- your code (EX stage) ----
    assign EX_funct = EX_extend[5:0]; //43
    assign alu1 = EX_rd1;             //44
    assign alu2 = EX_ALUSrc ? EX_extend : EX_rd2; //45

    always_comb begin
        ALUctl = 4'b0010; //46 (default: add)
        if (EX_ALUOp == 2'b10) begin
            case (EX_funct)
                6'b100000: ALUctl = 4'b0010; // add
                6'b100010: ALUctl = 4'b0110; // sub
                6'b100100: ALUctl = 4'b0000; // and
                6'b100101: ALUctl = 4'b0001; // or
                6'b101010: ALUctl = 4'b0111; // slt
                default:   ALUctl = 4'b0010;
            endcase
        end
    end

    assign EX_RegRd = EX_RegDst ? EX_rd : EX_rt; //47

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
    always_ff @(posedge clock_mips) begin
        EXMEM_ALUOut   <= EX_ALUOut;   //48
        EXMEM_rd2      <= EX_rd2;      //49
        EXMEM_RegRd    <= EX_RegRd;    //50
        EXMEM_RegWrite <= EX_RegWrite; //51
        EXMEM_MemWrite <= EX_MemWrite; //52
        EXMEM_MemRead  <= EX_MemRead;  //53
        EXMEM_MemtoReg <= EX_MemtoReg; //54
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

    // ---- your code (MEM stage) ----
    assign Writedata_mips    = MEM_rd2;       //62
    assign address_mips      = MEM_ALUOut;    //63
    assign memory_write_mips = MEM_MemWrite;  //64
    assign memory_read_mips  = MEM_MemRead;   //65
    assign MEM_memout        = Readdata_mips; //66

    // **** SAVE TO PIPELINE REGISTERS
    always_ff @(posedge clock_mips) begin
        MEMWB_memout   <= MEM_memout;   //67
        MEMWB_ALUOut   <= MEM_ALUOut;   //68
        MEMWB_RegRd    <= MEM_RegRd;    //69
        MEMWB_RegWrite <= MEM_RegWrite; //70
        MEMWB_MemtoReg <= MEM_MemtoReg; //71
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

    // ---- your code (WB stage) ----
    assign WB_wd = WB_MemtoReg ? WB_memout : WB_ALUOut; //77

    always_ff @(negedge clock_mips) begin
        if (WB_RegWrite)
            Registers[WB_wn] <= WB_wd;
    end

    // NOTE: overflow_mips and invalid_mips are declared as outputs in your
    // original VHDL entity but were never actually driven anywhere in the
    // architecture body - that's a pre-existing gap in the original file,
    // not something introduced in this conversion. Left undriven here too,
    // to keep this a faithful 1:1 port. Worth wiring these up for real when
    // you extend the ISA (overflow especially, once you add more arithmetic).

endmodule
