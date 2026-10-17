module log2_lut (
    input  logic [3:0]  idx,
    output logic [9:0]  frac_log2
);
    always_comb begin
        case (idx)
            4'd0:  frac_log2 = 10'd0;
            4'd1:  frac_log2 = 10'd90;
            4'd2:  frac_log2 = 10'd174;
            4'd3:  frac_log2 = 10'd254;
            4'd4:  frac_log2 = 10'd330;
            4'd5:  frac_log2 = 10'd402;
            4'd6:  frac_log2 = 10'd470;
            4'd7:  frac_log2 = 10'd536;
            4'd8:  frac_log2 = 10'd599;
            4'd9:  frac_log2 = 10'd659;
            4'd10: frac_log2 = 10'd717;
            4'd11: frac_log2 = 10'd773;
            4'd12: frac_log2 = 10'd827;
            4'd13: frac_log2 = 10'd879;
            4'd14: frac_log2 = 10'd929;
            4'd15: frac_log2 = 10'd977;
            default: frac_log2 = 10'd0;
        endcase
    end
endmodule
