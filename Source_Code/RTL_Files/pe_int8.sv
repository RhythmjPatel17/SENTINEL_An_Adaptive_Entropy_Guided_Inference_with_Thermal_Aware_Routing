import sentinel_pkg::*;

module pe_int8 (
    input  logic                    clk,
    input  logic                    rst_n,
    input  logic                    clear_acc,
    input  logic                    en,
    input  logic signed [ACT_W-1:0] act_in,
    input  logic signed [WGT_W-1:0] wgt_in,
    output logic signed [ACC_W-1:0] acc_out
);
    logic signed [ACT_W+WGT_W-1:0] product;
    logic signed [ACC_W-1:0]       acc_reg;

    assign product = act_in * wgt_in;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            acc_reg <= '0;
        else if (clear_acc)
            acc_reg <= en ? ACC_W'(product) : '0;
        else if (en)
            acc_reg <= acc_reg + ACC_W'(product);
    end

    assign acc_out = acc_reg;
endmodule
