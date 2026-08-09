module ALU (
    input  logic [3:0] ALUctl_alu,    // control
    input  logic       A_alu,         // A input
    input  logic       B_alu,         // B input
    input  logic       carryin_alu,   // arithmetic carry in
    input  logic       less_alu,
    output logic       ALUresult_alu, // result
    output logic       carryout_alu   // arithmetic carry out
);

    logic [1:0] Operation;
    logic Ainvert, Binvert, a_in, b_in, result;

    assign Operation = ALUctl_alu[1:0];
    assign Binvert   = ALUctl_alu[2];
    assign Ainvert   = ALUctl_alu[3];

    // Ainvert 2-to-1 mux
    assign a_in = Ainvert ? ~A_alu : A_alu;

    // Binvert 2-to-1 mux
    assign b_in = Binvert ? ~B_alu : B_alu;

    // Operation 4-to-1 mux
    always_comb begin
        case (Operation)
            2'b00:   result = a_in & b_in;                    // AND
            2'b01:   result = a_in | b_in;                    // OR
            2'b10:   result = a_in ^ b_in ^ carryin_alu;       // add
            default: result = less_alu;                       // slt
        endcase
    end

    // carry-out logic (only meaningful for add/sub operations)
    always_comb begin
        case (Operation)
            2'b10, 2'b11: carryout_alu = (a_in & b_in) | (carryin_alu & b_in) | (a_in & carryin_alu);
            default:      carryout_alu = 1'b0;
        endcase
    end

    assign ALUresult_alu = result;

endmodule
