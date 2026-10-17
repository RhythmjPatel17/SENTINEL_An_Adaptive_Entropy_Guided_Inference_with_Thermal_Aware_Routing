import sentinel_pkg::*;

module pointwise_conv_unit (
    input  logic                       clk,
    input  logic                       rst_n,

    input  logic                       start,
    input  logic [9:0]                 in_ch,

    input  logic signed [ACT_W-1:0]    act_stream_in,
    input  logic                       act_stream_valid,
    input  logic signed [WGT_W-1:0]    wgt_stream_in [NUM_PE],

    input  activation_e                act_sel,
    input  logic [15:0]                requant_mult,
    input  logic [4:0]                 requant_shift,
    input  logic                       use_residual,
    input  logic signed [ACT_W-1:0]    residual_in [NUM_PE],

    output logic                       done,
    output logic signed [ACT_W-1:0]    pixel_out [NUM_PE]
);
    logic [10:0] cycle_cnt;
    logic clear_acc, running;
    logic signed [ACC_W-1:0] acc_out [NUM_PE];

    pe_array u_pe_array (
        .clk(clk), .rst_n(rst_n),
        .clear_acc(clear_acc), .en(act_stream_valid && running),
        .act_broadcast(1'b1),
        .act_in_bcast(act_stream_in),
        .act_in_lane('{default: '0}),
        .wgt_in_lane(wgt_stream_in),
        .acc_out_lane(acc_out)
    );

    typedef enum logic [1:0] {S_IDLE, S_RUN, S_DONE} state_t;
    state_t state;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE; cycle_cnt <= '0; clear_acc <= 1'b0; running <= 1'b0; done <= 1'b0;
        end else begin
            done <= 1'b0;
            unique case (state)
                S_IDLE: begin
                    clear_acc <= 1'b0;
                    if (start) begin
                        cycle_cnt <= '0;
                        clear_acc <= 1'b1;
                        running   <= 1'b1;
                        state     <= S_RUN;
                    end
                end
                S_RUN: begin
                    clear_acc <= 1'b0;
                    if (act_stream_valid) begin
                        if (cycle_cnt == in_ch - 1) begin
                            running <= 1'b0;
                            state   <= S_DONE;
                        end else begin
                            cycle_cnt <= cycle_cnt + 1'b1;
                        end
                    end
                end
                S_DONE: begin
                    done  <= 1'b1;
                    state <= S_IDLE;
                end
                default: state <= S_IDLE;
            endcase
        end
    end

    genvar a;
    generate
        for (a = 0; a < NUM_PE; a++) begin : g_act
            logic signed [ACT_W-1:0] pre_residual;
            logic signed [ACT_W+1:0] summed;
            activation_unit u_act (
                .acc_in(acc_out[a]), .act_sel(act_sel),
                .requant_mult(requant_mult), .requant_shift(requant_shift),
                .act_out(pre_residual)
            );
            assign summed = use_residual ? ($signed({pre_residual[7], pre_residual}) +
                                             $signed({residual_in[a][7], residual_in[a]}))
                                          : $signed({pre_residual[7], pre_residual});
            assign pixel_out[a] = (summed > 9'sd127) ? 8'sd127 :
                                   (summed < -9'sd128) ? -8'sd128 : summed[7:0];
        end
    endgenerate
endmodule
