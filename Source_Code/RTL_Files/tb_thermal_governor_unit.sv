`timescale 1ns/1ps
module tb_thermal_governor_unit;
    logic clk = 0, rst_n;
    logic start, done;
    logic signed [15:0] t_junction_q8_8;
    logic [15:0] threshold_out_q0_16;

    always #2 clk = ~clk;

    thermal_governor_unit dut (
        .clk(clk), .rst_n(rst_n), .start(start),
        .t_junction_q8_8(t_junction_q8_8),
        .done(done), .threshold_out_q0_16(threshold_out_q0_16)
    );

    task automatic run_case(input real temp_c, input real expect_tau, input real tol);
        real got_tau;
        begin
            t_junction_q8_8 = 16'($rtoi(temp_c * 256.0));
            @(posedge clk); start = 1'b1;
            @(posedge clk); start = 1'b0;
            wait (done); @(posedge clk);
            got_tau = $itor(threshold_out_q0_16) / 65536.0;
            $display("Tj=%.1fC  tau=%.4f (expect ~%.4f)", temp_c, got_tau, expect_tau);
            if (got_tau < expect_tau - tol || got_tau > expect_tau + tol)
                $error("Tj=%.1fC threshold out of tolerance", temp_c);
        end
    endtask

    initial begin
        rst_n = 0; start = 0;
        repeat (4) @(posedge clk); rst_n = 1; repeat (4) @(posedge clk);

        run_case(55.0, 0.98, 0.02);
        run_case(60.0, 0.94, 0.02);
        run_case(65.0, 0.90, 0.02);
        run_case(70.0, 0.86, 0.02);
        run_case(75.0, 0.82, 0.02);
        run_case(80.0, 0.78, 0.02);
        run_case(85.0, 0.74, 0.02);
        run_case(150.0, 0.62, 0.02);

        $display("tb_thermal_governor_unit: all cases completed.");
        $finish;
    end
endmodule
