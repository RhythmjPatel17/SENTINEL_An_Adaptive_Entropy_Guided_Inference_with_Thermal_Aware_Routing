module leading_one_detector (
    input  logic [15:0] val_in,
    output logic [3:0]  msb_pos,
    output logic        valid
);
    always_comb begin
        valid   = |val_in;
        msb_pos = 4'd0;
        for (int b = 15; b >= 0; b--)
            if (val_in[b]) begin
                msb_pos = b[3:0];
                break;
            end
    end
endmodule
