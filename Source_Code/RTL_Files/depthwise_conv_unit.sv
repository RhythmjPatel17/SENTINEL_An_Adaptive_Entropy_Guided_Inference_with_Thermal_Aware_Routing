import sentinel_pkg::*;

module depthwise_conv_unit (
    input  logic                       clk,
    input  logic                       rst_n,

    input  logic                       start,
    input  logic [2:0]                 kernel,
    input  logic signed [ACT_W-1:0]    win_in [NUM_PE][MAX_KSIZE][MAX_KSIZE],
    input  logic signed [WGT_W-1:0]    wgt_in [NUM_PE][MAX_KSIZE][MAX_KSIZE],

    input  activation_e                act_sel,
    input  logic [15:0]                requant_mult,
    input  logic [4:0]                 requant_shift,

    output logic                       done,
    output logic signed [ACT_W-1:0]    pixel_out [NUM_PE]
);
    logic [3:0]  tap_row, tap_col;
    logic        clear_acc, pe_en;
    logic signed [ACT_W-1:0] act_stream [NUM_PE];
    logic signed [WGT_W-1:0] wgt_stream [NUM_PE];
    logic signed [ACC_W-1:0] acc_out [NUM_PE];

    genvar g;
    generate
        for (g = 0; g < NUM_PE; g++) begin : g_stream
            assign act_stream[g] = win_in[g][tap_row][tap_col];
            assign wgt_stream[g] = wgt_in[g][tap_row][tap_col];
        end
    endgenerate

    pe_array u_pe_array (
        .clk(clk), .rst_n(rst_n),
        .clear_acc(clear_acc), .en(pe_en),
        .act_broadcast(1'b0),
        .act_in_bcast('0),
        .act_in_lane(act_stream),
        .wgt_in_lane(wgt_stream),
        .acc_out_lane(acc_out)
    );

    typedef enum logic [1:0] {S_IDLE, S_RUN, S_DONE} state_t;
    state_t state;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE; tap_row <= '0; tap_col <= '0;
            clear_acc <= 1'b0; pe_en <= 1'b0; done <= 1'b0;
        end else begin
            done <= 1'b0;
            unique case (state)
                S_IDLE: begin
                    clear_acc <= 1'b0;
                    if (start) begin
                        tap_row <= '0; tap_col <= '0;
                        clear_acc <= 1'b1; pe_en <= 1'b1;
                        state <= S_RUN;
                    end
                end
                S_RUN: begin
                    clear_acc <= 1'b0;
                    if (tap_col == kernel-1) begin
                        tap_col <= '0;
                        if (tap_row == kernel-1) begin
                            pe_en <= 1'b0;
                            state <= S_DONE;
                        end else begin
                            tap_row <= tap_row + 1'b1;
                        end
                    end else begin
                        tap_col <= tap_col + 1'b1;
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
            activation_unit u_act (
                .acc_in(acc_out[a]), .act_sel(act_sel),
                .requant_mult(requant_mult), .requant_shift(requant_shift),
                .act_out(pixel_out[a])
            );
        end
    endgenerate
endmodule
