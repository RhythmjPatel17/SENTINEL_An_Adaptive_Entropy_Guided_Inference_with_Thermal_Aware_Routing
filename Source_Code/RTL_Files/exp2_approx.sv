module exp2_approx (
    input  logic signed [15:0] y_q6_10,
    output logic        [15:0] exp2_out_q0_16
);
    logic signed [15:0] neg_y;
    logic [5:0]  k_int;
    logic [9:0]  frac_q0_10;
    logic [3:0]  frac_idx;
    logic [15:0] lut_val;

    assign neg_y = -y_q6_10;

    always_comb begin
        k_int      = 6'd0;
        frac_q0_10 = 10'd0;
        frac_idx   = 4'd0;
        if (y_q6_10 >= 0) begin
            exp2_out_q0_16 = 16'hFFFF;
        end else begin
            k_int      = neg_y[15:10];
            frac_q0_10 = neg_y[9:0];
            frac_idx   = frac_q0_10[9:6];
            exp2_out_q0_16 = (k_int > 6'd16) ? 16'd0 : (lut_val >> k_int);
        end
    end

    exp2_lut u_lut (.idx(frac_idx), .frac_exp2(lut_val));
endmodule
