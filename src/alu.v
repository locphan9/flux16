module alu (
    input  wire [15:0] a,
    input  wire [15:0] b,
    input  wire [2:0]  alu_op,
    output reg  [15:0] out,
    output reg  zero,
    output reg  neg,
    output reg  overflow,
    output reg  carry
);
    reg [16:0] sum_carry;
    always @(*) begin
        overflow = 1'b0; // Default value for overflow
        carry = 1'b0;   // Default value for carry
        neg = 1'b0;     // Default value for negative
        zero = 1'b0;    // Default value for zero
        sum_carry = 17'b0; // Default value for sum_carry
        case (alu_op)
            3'b000: begin
                sum_carry = {1'b0, a} + {1'b0, b};
                carry = sum_carry[16]; // ADD
                out = sum_carry[15:0];
                overflow  = (a[15] == b[15]) && (out[15] != a[15]);
            end
            3'b001:  begin // SUB
                sum_carry = {1'b0, a} - {1'b0, b};
                carry = sum_carry[16];
                out = sum_carry[15:0];
                overflow = (a[15] != b[15]) && (out[15] != a[15]);
            end
            3'b010:  begin
            out = a & b;         // AND
            end
            3'b011:  begin
            out = a | b;         // OR
            end
            3'b100:  begin
            out = a ^ b;         // XOR
            end
            3'b101:  begin
            out = a << b[3:0];   // SLL (Shift Left Logical)
            end
            3'b110:  begin
            out = a >> b[3:0];   // SRL (Shift Right Logical)
            end
            3'b111:  begin
            out = ($signed(a) < $signed(b)) ? 16'd1 : 16'd0; // SLT (Set Less Than)
            end
            default: out = 16'h0000;
        endcase
        neg = out[15];
        zero = (out == 16'b0);
    end
endmodule
