module exp2_lut (
    input  logic [3:0]  idx,
    output logic [15:0] frac_exp2
);
    always_comb begin
        case (idx)
            4'd0:  frac_exp2 = 16'd65535;
            4'd1:  frac_exp2 = 16'd62936;
            4'd2:  frac_exp2 = 16'd60466;
            4'd3:  frac_exp2 = 16'd58154;
            4'd4:  frac_exp2 = 16'd55949;
            4'd5:  frac_exp2 = 16'd53862;
            4'd6:  frac_exp2 = 16'd51878;
            4'd7:  frac_exp2 = 16'd49991;
            4'd8:  frac_exp2 = 16'd48197;
            4'd9:  frac_exp2 = 16'd46490;
            4'd10: frac_exp2 = 16'd44866;
            4'd11: frac_exp2 = 16'd43321;
            4'd12: frac_exp2 = 16'd41851;
            4'd13: frac_exp2 = 16'd40451;
            4'd14: frac_exp2 = 16'd39119;
            4'd15: frac_exp2 = 16'd37851;
            default: frac_exp2 = 16'd32768;
        endcase
    end
endmodule
