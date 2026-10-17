import sentinel_pkg::*;

module pe_array (
    input  logic                              clk,
    input  logic                              rst_n,
    input  logic                              clear_acc,
    input  logic                              en,
    input  logic                              act_broadcast,
    input  logic signed [ACT_W-1:0]           act_in_bcast,
    input  logic signed [ACT_W-1:0]           act_in_lane [NUM_PE],
    input  logic signed [WGT_W-1:0]           wgt_in_lane [NUM_PE],
    output logic signed [ACC_W-1:0]           acc_out_lane [NUM_PE]
);
    genvar i;
    generate
        for (i = 0; i < NUM_PE; i++) begin : g_pe
            logic signed [ACT_W-1:0] act_sel;
            assign act_sel = act_broadcast ? act_in_bcast : act_in_lane[i];

            pe_int8 u_pe (
                .clk       (clk),
                .rst_n     (rst_n),
                .clear_acc (clear_acc),
                .en        (en),
                .act_in    (act_sel),
                .wgt_in    (wgt_in_lane[i]),
                .acc_out   (acc_out_lane[i])
            );
        end
    endgenerate
endmodule
