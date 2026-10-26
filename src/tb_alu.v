`timescale 1ns/1ps

// Self-checking testbench for the Flux16 16-bit ALU.
// Phases: (1) full corner-value cross on all 8 opcodes, (2) shift-amount sweep,
//         (3) biased constrained-random.
// Checks: independent reference model, flag invariants, X guards on stimulus and outputs.
// Metric: flag-bin functional coverage (testbench-level, not RTL code coverage).
// Random stimulus uses $urandom with the simulator's default seed -> repeatable runs.

module tbt_alu;

    reg  [15:0] a;
    reg  [15:0] b;
    reg  [2:0]  alu_op;
    wire [15:0] out;
    wire        zero;
    wire        neg;
    wire        overflow;
    wire        carry;

    // Simulation metrics
    integer test_count  = 0;
    integer error_count = 0;   // reference-model mismatches and X outputs
    integer inv_count   = 0;   // flag-invariant violations
    integer x_err_count = 0;   // X/Z on stimulus

    // Loop variables
    integer i, j, op_i, sh;

    // Reference model expected outputs
    reg [15:0] exp_out;
    reg        exp_zero;
    reg        exp_neg;
    reg        exp_overflow;
    reg        exp_carry;

    // 10 key corner values
    reg [15:0] corner_cases [0:9];

    // Stimulus generation scratchpad
    reg [15:0] rand_a;
    reg [15:0] rand_b;
    reg [2:0]  rand_op;
    integer    idx_a, idx_b, bias_pick_a, bias_pick_b;

    // Flag-bin coverage: index = op*4 + flag (0=zero, 1=neg, 2=overflow, 3=carry)
    integer cov_hit [0:31];
    integer cov_holes;
    integer c_op, c_f, c_reach, c_total, c_covered;

    // DUT
    alu uut (
        .a(a),
        .b(b),
        .alu_op(alu_op),
        .out(out),
        .zero(zero),
        .neg(neg),
        .overflow(overflow),
        .carry(carry)
    );

    // -------------------------------------------------------------
    // Reference model: wide-integer math, written from the spec
    // (carry on SUB is the borrow flag: a < b unsigned)
    // -------------------------------------------------------------
    task alu_ref_model;
        input [2:0]  op;
        input [15:0] in_a;
        input [15:0] in_b;

        integer signed_a, signed_b, signed_res;
        reg [31:0] unsigned_a, unsigned_b, unsigned_res;
        begin
            exp_carry    = 1'b0;
            exp_overflow = 1'b0;

            signed_a   = (in_a[15]) ? (in_a | 32'hFFFF0000) : in_a;
            signed_b   = (in_b[15]) ? (in_b | 32'hFFFF0000) : in_b;
            unsigned_a = {16'd0, in_a};
            unsigned_b = {16'd0, in_b};

            case (op)
                3'b000: begin // ADD
                    unsigned_res = unsigned_a + unsigned_b;
                    signed_res   = signed_a + signed_b;
                    exp_out      = unsigned_res[15:0];
                    exp_carry    = (unsigned_res >= 32'd65536);
                    exp_overflow = (signed_res > 32767) || (signed_res < -32768);
                end

                3'b001: begin // SUB
                    unsigned_res = unsigned_a - unsigned_b;
                    signed_res   = signed_a - signed_b;
                    exp_out      = unsigned_res[15:0];
                    exp_carry    = (unsigned_a < unsigned_b); // borrow
                    exp_overflow = (signed_res > 32767) || (signed_res < -32768);
                end

                3'b010: exp_out = in_a & in_b;
                3'b011: exp_out = in_a | in_b;
                3'b100: exp_out = in_a ^ in_b;
                3'b101: exp_out = in_a << in_b[3:0];
                3'b110: exp_out = in_a >> in_b[3:0];
                3'b111: exp_out = (signed_a < signed_b) ? 16'd1 : 16'd0;
                default: exp_out = 16'h0000;
            endcase

            exp_zero = (exp_out == 16'h0000);
            exp_neg  = exp_out[15];
        end
    endtask

    // -------------------------------------------------------------
    // Driver, input guard, scoreboard, invariants, coverage sampling
    // -------------------------------------------------------------
    task run_test;
        input [15:0] test_a;
        input [15:0] test_b;
        input [2:0]  test_op;
        begin
            a      = test_a;
            b      = test_b;
            alu_op = test_op;
            #10;

            test_count = test_count + 1;

            // Guard 1: X/Z on stimulus (should never happen)
            if ((^{a, b, alu_op}) === 1'bx) begin
                $display("FATAL [X Stimulus] Test #%0d: a=%h b=%h op=%b", test_count, a, b, alu_op);
                x_err_count = x_err_count + 1;
            end

            alu_ref_model(alu_op, a, b);

            // Guard 2: X/Z on DUT outputs
            if ((^{out, zero, neg, overflow, carry}) === 1'bx) begin
                $display("ERROR [X Output] Test #%0d: out=%h Z=%b N=%b V=%b C=%b",
                         test_count, out, zero, neg, overflow, carry);
                error_count = error_count + 1;
            end

            // Reference-model comparison
            if ((out      !== exp_out)      ||
                (zero     !== exp_zero)     ||
                (neg      !== exp_neg)      ||
                (overflow !== exp_overflow) ||
                (carry    !== exp_carry)) begin
                $display("ERROR [Mismatch] Test #%0d | Op: %b | A: %h | B: %h", test_count, alu_op, a, b);
                $display("  Expected: Out=%h Z=%b N=%b V=%b C=%b", exp_out, exp_zero, exp_neg, exp_overflow, exp_carry);
                $display("  Actual:   Out=%h Z=%b N=%b V=%b C=%b", out, zero, neg, overflow, carry);
                error_count = error_count + 1;
            end

            // Flag invariants checked directly on DUT outputs (independent of the model)
            if (zero !== (out == 16'h0000)) begin
                $display("ERROR [Invariant] Test #%0d: zero flag inconsistent with out=%h", test_count, out);
                inv_count = inv_count + 1;
            end
            if (neg !== out[15]) begin
                $display("ERROR [Invariant] Test #%0d: neg flag inconsistent with out=%h", test_count, out);
                inv_count = inv_count + 1;
            end
            if (alu_op > 3'b001 && (carry !== 1'b0 || overflow !== 1'b0)) begin
                $display("ERROR [Invariant] Test #%0d: carry/overflow set on non-arithmetic op %b", test_count, alu_op);
                inv_count = inv_count + 1;
            end

            // Flag-bin coverage sampling (observed DUT flags)
            if (zero     === 1'b1) cov_hit[alu_op*4 + 0] = cov_hit[alu_op*4 + 0] + 1;
            if (neg      === 1'b1) cov_hit[alu_op*4 + 1] = cov_hit[alu_op*4 + 1] + 1;
            if (overflow === 1'b1) cov_hit[alu_op*4 + 2] = cov_hit[alu_op*4 + 2] + 1;
            if (carry    === 1'b1) cov_hit[alu_op*4 + 3] = cov_hit[alu_op*4 + 3] + 1;
        end
    endtask

    // -------------------------------------------------------------
    // Main test execution
    // -------------------------------------------------------------
    initial begin
        $dumpfile("alu_tb.vcd");
        $dumpvars(0, tbt_alu);

        for (i = 0; i < 32; i = i + 1) cov_hit[i] = 0;

        corner_cases[0] = 16'h0000; // Zero
        corner_cases[1] = 16'h0001; // +1
        corner_cases[2] = 16'h0002; // Small positive
        corner_cases[3] = 16'h7FFE; // Max Pos - 1
        corner_cases[4] = 16'h7FFF; // Max Pos (32767)
        corner_cases[5] = 16'h8000; // Max Neg (-32768)
        corner_cases[6] = 16'h8001; // Max Neg + 1
        corner_cases[7] = 16'hFFFE; // -2 signed / 65534 unsigned
        corner_cases[8] = 16'hFFFF; // -1 signed / 65535 unsigned
        corner_cases[9] = 16'h5555; // Alternating bit pattern

        // Phase 1: every corner value against every corner value, all 8 opcodes
        $display("---------------------------------------------------------");
        $display("Phase 1: Directed corner cross (10 x 10 x 8 opcodes)");
        $display("---------------------------------------------------------");
        for (op_i = 0; op_i < 8; op_i = op_i + 1) begin
            for (i = 0; i < 10; i = i + 1) begin
                for (j = 0; j < 10; j = j + 1) begin
                    run_test(corner_cases[i], corner_cases[j], op_i[2:0]);
                end
            end
        end

        // Phase 2: shift-amount sweep (0..15) for SLL and SRL
        $display("---------------------------------------------------------");
        $display("Phase 2: Directed shift-amount sweep");
        $display("---------------------------------------------------------");
        for (sh = 0; sh < 16; sh = sh + 1) begin
            run_test(16'h0001, sh[15:0], 3'b101);
            run_test(16'hA5A5, sh[15:0], 3'b101);
            run_test(16'h8001, sh[15:0], 3'b101);
            run_test(16'h0001, sh[15:0], 3'b110);
            run_test(16'hA5A5, sh[15:0], 3'b110);
            run_test(16'h8001, sh[15:0], 3'b110);
        end

        // Phase 3: biased constrained-random (30% corner-biased per operand)
        $display("---------------------------------------------------------");
        $display("Phase 3: Constrained-random (10,000 vectors)");
        $display("---------------------------------------------------------");
        for (i = 0; i < 10000; i = i + 1) begin
            bias_pick_a = $urandom_range(0, 99);
            bias_pick_b = $urandom_range(0, 99);

            if (bias_pick_a < 30) begin
                idx_a  = $urandom_range(0, 9);
                rand_a = corner_cases[idx_a];
            end else begin
                rand_a = $urandom;
            end

            if (bias_pick_b < 30) begin
                idx_b  = $urandom_range(0, 9);
                rand_b = corner_cases[idx_b];
            end else begin
                rand_b = $urandom;
            end

            rand_op = $urandom_range(0, 7);
            run_test(rand_a, rand_b, rand_op);
        end

        // Coverage report: reachable bins only
        //   zero: all opcodes | neg: ops 0-6 (SLT result is 0 or 1) | overflow, carry: ADD/SUB only
        c_total = 0; c_covered = 0; cov_holes = 0;
        $display("---------------------------------------------------------");
        $display("Flag-bin coverage (flag observed high, per opcode)");
        for (c_op = 0; c_op < 8; c_op = c_op + 1) begin
            for (c_f = 0; c_f < 4; c_f = c_f + 1) begin
                c_reach = (c_f == 0) ? 1 :
                          (c_f == 1) ? (c_op <= 6) :
                                       (c_op <= 1);
                if (c_reach) begin
                    c_total = c_total + 1;
                    if (cov_hit[c_op*4 + c_f] > 0) c_covered = c_covered + 1;
                    else begin
                        cov_holes = cov_holes + 1;
                        $display("  HOLE: op=%0d flag=%0d never observed high", c_op, c_f);
                    end
                end
            end
        end
        $display("Reachable flag bins covered: %0d / %0d", c_covered, c_total);

        // Sign-off summary
        $display("=========================================================");
        $display("Verification Sign-off Summary");
        $display("Total Vectors Executed : %0d", test_count);
        $display("Input X/Z Faults       : %0d", x_err_count);
        $display("Functional Mismatches  : %0d", error_count);
        $display("Invariant Violations   : %0d", inv_count);
        $display("Flag-bin Coverage Holes: %0d", cov_holes);
        if (error_count == 0 && x_err_count == 0 && inv_count == 0 && cov_holes == 0) begin
            $display("STATUS                 : PASSED");
            $display("=========================================================");
            $finish(0);
        end else begin
            $display("STATUS                 : FAILED");
            $display("=========================================================");
            $finish(1);
        end
    end

endmodule
