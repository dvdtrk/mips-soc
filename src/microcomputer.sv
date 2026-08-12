module microcomputer (
    input  logic       CLOCK_50,    // 50MHz clock on the DE10-Lite board
    input  logic [1:0] KEY,         // keys/buttons (KEY[0]-KEY[1])
    input  logic [9:0] SW,          // switches (SW[9]..SW[0])
    output logic [9:0] LEDR,        // LEDs (unused - see note below)
    output logic [6:0] HEX0,        // 7-segment display, digit 0
    output logic [6:0] HEX1,        // 7-segment display, digit 1
    output logic [6:0] HEX2,        // 7-segment display, digit 2
    output logic [6:0] HEX3,        // 7-segment display, digit 3
    output logic [6:0] HEX4,        // 7-segment display, digit 4
    output logic [6:0] HEX5         // 7-segment display, digit 5
);

    //---- Signal declarations ----
    logic        reset;
    logic        clock;
    logic [31:0] instruction;
    logic [31:0] pc;

    logic [31:0] address;
    logic [31:0] Writedata;
    logic        memory_read, memory_write;
    logic [31:0] Readdata;

    logic [3:0]  plusone, plusone1, plusone2, plusone3, plusone4, plusone5, plusone6, plusone7; // 7-seg digit values

    logic [31:0] counter_out;
    logic [1:0]  flipflops;
    logic        counter_set;
    localparam int COUNTER_SIZE = 16;

    initial begin
        counter_out = 32'h00000000;
        flipflops   = 2'b00;
    end

    //*****************************************************************
    // reset / clock
    //*****************************************************************
    assign reset = ~KEY[1]; // KEY[1] is reset
    assign clock = ~KEY[0]; // KEY[0] used as the clock (50MHz is too fast)
                            // may need debouncing circuit

    assign counter_set = flipflops[0] ^ flipflops[1];

    always_ff @(posedge CLOCK_50) begin
        flipflops[0] <= ~KEY[0];
        flipflops[1] <= flipflops[0];
        if (counter_set)
            counter_out <= 32'h00000000;
        else if (!counter_out[COUNTER_SIZE])
            counter_out <= counter_out + 1;
        // else: clock <= flipflops[1]; (unused / commented out in original too)
    end

    //---- Component instantiations ----
    mips CPU_1 (
        .clock_mips       (clock),
        .reset_mips       (reset),
        .pc_mips          (pc),
        .instruction_mips (instruction),
        .address_mips     (address),
        .Writedata_mips   (Writedata),
        .overflow_mips    (),           // not wired up in original design either
        .invalid_mips     (),           // not wired up in original design either
        .memory_read_mips (memory_read),
        .memory_write_mips(memory_write),
        .Readdata_mips    (Readdata)
    );

    inst_memory_128B MEMORY_1 (
        .clock_im      (clock),
        .reset_im      (reset),
        .pc_im         (pc),
        .instruction_im(instruction)
    );

    data_memory_64B MEMORY_2 (
        .clock_dm        (clock),
        .reset_dm        (reset),
        .address_dm      (address),
        .Writedata_dm    (Writedata),
        .memory_read_dm  (memory_read),
        .memory_write_dm (memory_write),
        .Readdata_dm     (Readdata)
    );

    // PC, instruction, Writedata (=rdata2), address (=ALUresult), Readdata
    always_comb begin
        if (reset) begin
            plusone  = 4'b0000;
            plusone1 = 4'b0000;
            plusone2 = 4'b0000;
            plusone3 = 4'b0000;
            plusone4 = 4'b0000;
            plusone5 = 4'b0000;
            plusone6 = 4'b0000;
            plusone7 = 4'b0000;

        end else if (SW == 10'b0000000001) begin // PC
            plusone  = pc[3:0];
            plusone1 = pc[7:4];
            plusone2 = pc[11:8];
            plusone3 = pc[15:12];
            plusone4 = pc[19:16];
            plusone5 = pc[23:20];

        end else if (SW == 10'b0000000010) begin // instruction
            plusone  = instruction[3:0];
            plusone1 = instruction[7:4];
            plusone2 = instruction[11:8];
            plusone3 = instruction[15:12];
            plusone4 = instruction[19:16];
            plusone5 = pc[3:0];

        end else if (SW == 10'b0000000100) begin // Writedata (=rdata2)
            plusone  = Writedata[3:0];
            plusone1 = Writedata[7:4];
            plusone2 = Writedata[11:8];
            plusone3 = Writedata[15:12];
            plusone4 = Writedata[19:16];
            plusone5 = pc[3:0];

        end else if (SW == 10'b0000001000) begin // address (=ALUresult)
            plusone  = address[3:0];
            plusone1 = address[7:4];
            plusone2 = address[11:8];
            plusone3 = address[15:12];
            plusone4 = address[19:16];
            plusone5 = pc[3:0];

        end else if (SW == 10'b0000010000) begin // Readdata
            plusone  = Readdata[3:0];
            plusone1 = Readdata[7:4];
            plusone2 = Readdata[11:8];
            plusone3 = Readdata[15:12];
            plusone4 = Readdata[19:16];
            plusone5 = pc[3:0];

        end else begin
            plusone  = 4'b0000;
            plusone1 = 4'b0000;
            plusone2 = 4'b0000;
            plusone3 = 4'b0000;
            plusone4 = 4'b0000;
            plusone5 = pc[3:0];
        end
    end

    hex h0 (.i(plusone),  .o(HEX0));
    hex h1 (.i(plusone1), .o(HEX1));
    hex h2 (.i(plusone2), .o(HEX2));
    hex h3 (.i(plusone3), .o(HEX3));
    hex h4 (.i(plusone4), .o(HEX4));
    hex h5 (.i(plusone5), .o(HEX5));

    // NOTE: LEDR is declared as an output in the entity but is not driven
    // in the architecture - same pre-existing gap as overflow_mips/
    // invalid_mips, carried over faithfully rather than silently patched.
    // Worth wiring up when real debug/status LEDs are added.

endmodule