module log2_approx (
    input  logic [15:0]        val_q0_16,
    output logic signed [15:0] log2_out_q6_10,
    output logic               valid_nonzero
);
    logic [3:0]  msb_pos;
    logic        lod_valid;
    logic [15:0] shifted;
    logic [3:0]  f_idx;
    logic [9:0]  frac_log2;
    logic signed [5:0] int_part;

    leading_one_detector u_lod (
        .val_in  (val_q0_16),
        .msb_pos (msb_pos),
        .valid   (lod_valid)
    );

    assign shifted = val_q0_16 << (4'd15 - msb_pos);
    assign f_idx   = shifted[14:11];

    log2_lut u_lut (
        .idx       (f_idx),
        .frac_log2 (frac_log2)
    );

    assign int_part       = $signed({2'b00, msb_pos}) - 6'sd16;
    assign log2_out_q6_10 = (int_part <<< 10) + $signed({6'b0, frac_log2});
    assign valid_nonzero  = lod_valid;
endmodule
