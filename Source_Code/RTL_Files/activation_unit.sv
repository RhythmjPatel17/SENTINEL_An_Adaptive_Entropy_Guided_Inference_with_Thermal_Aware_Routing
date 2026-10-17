import sentinel_pkg::*;

module activation_unit (
    input  logic signed [ACC_W-1:0] acc_in,
    input  activation_e             act_sel,
    input  logic [15:0]             requant_mult,
    input  logic [4:0]              requant_shift,
    output logic signed [ACT_W-1:0] act_out
);
    logic signed [47:0]      requant_full;
    logic signed [ACC_W-1:0] requant_clamped;
    logic signed [ACT_W-1:0] requantized;
    logic signed [ACT_W-1:0] hsig;
    logic signed [15:0]      hswish_wide;
    logic signed [ACT_W-1:0] hswish_full;

    always_comb begin
        hsig        = 8'sd0;
        hswish_wide = 16'sd0;
        hswish_full = 8'sd0;

        requant_full    = acc_in * $signed({1'b0, requant_mult});
        requant_clamped = requant_full >>> requant_shift;
        if (requant_clamped > 127)       requantized = 8'sd127;
        else if (requant_clamped < -128) requantized = -8'sd128;
        else                              requantized = requant_clamped[7:0];

        unique case (act_sel)
            ACT_NONE: act_out = requantized;

            ACT_RELU6: act_out = (requantized < 0) ? 8'sd0 : requantized;

            ACT_HSIGMOID: begin
                hsig = ((requantized + 8'sd64) < 0) ? 8'sd0 :
                       (((requantized + 8'sd64) > 8'sd127) ? 8'sd127 : (requantized + 8'sd64));
                act_out = hsig;
            end

            ACT_HSWISH: begin
                hsig = ((requantized + 8'sd64) < 0) ? 8'sd0 :
                       (((requantized + 8'sd64) > 8'sd127) ? 8'sd127 : (requantized + 8'sd64));
                hswish_wide = requantized * hsig;
                hswish_full = hswish_wide >>> 7;
                act_out     = hswish_full;
            end

            default: act_out = requantized;
        endcase
    end
endmodule
