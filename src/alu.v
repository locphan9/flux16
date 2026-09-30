module alu (
    input  wire [15:0] a,
    input  wire [15:0] b,
    input  wire [2:0]  alu_op,
    output reg  [15:0] out,
    output wire        zero
);

    always @(*) begin
        case (alu_op)
            3'b000:  out = a + b;         // ADD
            3'b001:  out = a - b;         // SUB
            3'b010:  out = a & b;         // AND
            3'b011:  out = a | b;         // OR
            3'b100:  out = a ^ b;         // XOR
            3'b101:  out = a << b[3:0];   // SLL (Shift Left Logical)
            3'b110:  out = a >> b[3:0];   // SRL (Shift Right Logical)
            3'b111:  out = (a < b) ? 16'd1 : 16'd0; // SLT (Set Less Than)
            default: out = 16'b0;
        endcase
    end

    assign zero = (out == 16'b0);

endmodule
