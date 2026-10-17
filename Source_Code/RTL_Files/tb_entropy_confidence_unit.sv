`timescale 1ns/1ps
import sentinel_pkg::*;

module tb_entropy_confidence_unit;
    logic clk = 0, rst_n;
    logic start, done;
    logic [15:0] prob_in [NUM_CLASSES];
    logic signed [15:0] entropy_out_q8_8;
    logic [15:0] confidence_out_q0_16;

    always #2 clk = ~clk;

    entropy_confidence_unit dut (
        .clk(clk), .rst_n(rst_n), .start(start), .prob_in(prob_in),
        .done(done), .entropy_out_q8_8(entropy_out_q8_8),
        .confidence_out_q0_16(confidence_out_q0_16)
    );

    task automatic run_case(input string name, input logic [15:0] probs [NUM_CLASSES],
                             input real expect_h, input real expect_c, input real tol);
        real h_real, c_real;
        begin
            for (int i = 0; i < NUM_CLASSES; i++) prob_in[i] = probs[i];
            @(posedge clk); start = 1'b1;
            @(posedge clk); start = 1'b0;
            wait (done); @(posedge clk);

            h_real = $itor(entropy_out_q8_8) / 256.0;
            c_real = $itor(confidence_out_q0_16) / 65536.0;

            $display("[%s] H=%.4f (expect ~%.4f)  c=%.4f (expect ~%.4f)",
                      name, h_real, expect_h, c_real, expect_c);

            if (h_real < expect_h - tol || h_real > expect_h + tol)
                $error("[%s] entropy out of tolerance", name);
            if (c_real < expect_c - tol || c_real > expect_c + tol)
                $error("[%s] confidence out of tolerance", name);
        end
    endtask

    logic [15:0] uniform_probs [NUM_CLASSES];
    logic [15:0] onehot_probs  [NUM_CLASSES];

    logic [15:0] t1_probs [NUM_CLASSES];

    logic [15:0] t3_probs [NUM_CLASSES];

    initial begin
        rst_n = 0; start = 0;
        for (int i = 0; i < NUM_CLASSES; i++) prob_in[i] = '0;
        repeat (4) @(posedge clk); rst_n = 1; repeat (4) @(posedge clk);

        for (int i = 0; i < NUM_CLASSES; i++) uniform_probs[i] = 16'd8192;
        run_case("uniform", uniform_probs, 2.0794, 0.0, 0.15);

        onehot_probs[0] = 16'd65100;
        for (int i = 1; i < NUM_CLASSES; i++) onehot_probs[i] = 16'd62;
        run_case("near_one_hot", onehot_probs, 0.06, 0.97, 0.15);

        t1_probs[0] = 16'd57514; t1_probs[1] = 16'd1146; t1_probs[2] = 16'd1146;
        t1_probs[3] = 16'd1146;  t1_probs[4] = 16'd1146;  t1_probs[5] = 16'd1146;
        t1_probs[6] = 16'd1146;  t1_probs[7] = 16'd1146;
        run_case("table2_T1_like", t1_probs, 0.61, 0.707, 0.15);

        $display("tb_entropy_confidence_unit: all directed cases completed.");
        $finish;
    end
endmodule
