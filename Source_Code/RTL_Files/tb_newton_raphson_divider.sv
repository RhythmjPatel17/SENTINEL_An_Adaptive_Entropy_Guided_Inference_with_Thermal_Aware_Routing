`timescale 1ns/1ps
module tb_newton_raphson_divider;
    logic clk = 0, rst_n;
    logic start, done;
    logic signed [15:0] numerator_q8_8;
    logic [15:0] denominator_q8_8;
    logic signed [15:0] quotient_q8_8;

    always #2 clk = ~clk;

    newton_raphson_divider dut (
        .clk(clk), .rst_n(rst_n), .start(start),
        .numerator_q8_8(numerator_q8_8), .denominator_q8_8(denominator_q8_8),
        .done(done), .quotient_q8_8(quotient_q8_8)
    );

    task automatic run_case(input string name, input real num, input real den, input real tol);
        real expect_q, got_q;
        begin
            numerator_q8_8   = 16'($rtoi(num * 256.0));
            denominator_q8_8 = 16'($rtoi(den * 256.0));
            @(posedge clk); start = 1'b1;
            @(posedge clk); start = 1'b0;
            wait (done); @(posedge clk);
            got_q = $itor(quotient_q8_8) / 256.0;
            expect_q = num / den;
            $display("[%s] %.4f / %.4f = %.4f (expect %.4f)", name, num, den, got_q, expect_q);
            if (got_q < expect_q - tol || got_q > expect_q + tol)
                $error("[%s] out of tolerance", name);
        end
    endtask

    initial begin
        rst_n = 0; start = 0;
        repeat (4) @(posedge clk); rst_n = 1; repeat (4) @(posedge clk);

        run_case("H/lnC uniform", 2.0794, 2.0794, 0.02);
        run_case("H/lnC low-H",   0.61,   2.0794, 0.02);
        run_case("H/lnC high-H",  1.32,   2.0794, 0.02);
        run_case("deltaT/125",    10.0,   125.0,  0.01);

        $display("tb_newton_raphson_divider: all cases completed.");
        $finish;
    end
endmodule
