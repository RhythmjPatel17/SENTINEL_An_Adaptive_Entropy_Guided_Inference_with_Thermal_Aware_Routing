import sentinel_pkg::*;

module entropy_confidence_unit (
    input  logic                          clk,
    input  logic                          rst_n,
    input  logic                          start,
    input  logic [15:0]                   prob_in [NUM_CLASSES],
    output logic                          done,
    output logic signed [15:0]            entropy_out_q8_8,
    output logic [15:0]                   confidence_out_q0_16
);
    localparam int IDX_W = $clog2(NUM_CLASSES);

    localparam logic [15:0] LN2_Q1_15 = 16'd22713;

    localparam logic [15:0] LOG_C_Q8_8 = 16'd532;

    typedef enum logic [2:0] {S_IDLE, S_ACCUM, S_RESCALE, S_TO_NATS, S_DIVSTART, S_DIVWAIT, S_DONE} state_t;
    state_t state;

    logic [IDX_W-1:0]      idx;
    logic [15:0]            cur_prob;
    logic signed [15:0]     log2_val;
    logic                   log2_valid;
    logic [15:0]             neg_log2_u;
    logic [31:0]            term_q6_26;
    logic [39:0]            sum_acc_q6_26;

    logic [21:0]            sum_bits_q6_8;
    logic signed [15:0]     h_nats_q8_8;

    logic                   div_start, div_done;
    logic signed [15:0]     div_quotient_q8_8;

    assign cur_prob = prob_in[idx];

    log2_approx u_log2 (
        .val_q0_16       (cur_prob),
        .log2_out_q6_10  (log2_val),
        .valid_nonzero   (log2_valid)
    );

    assign neg_log2_u = log2_valid ? (16'(-log2_val)) : 16'd0;
    assign term_q6_26 = cur_prob * neg_log2_u;

    newton_raphson_divider u_div (
        .clk               (clk),
        .rst_n             (rst_n),
        .start             (div_start),
        .numerator_q8_8    (h_nats_q8_8),
        .denominator_q8_8  (LOG_C_Q8_8),
        .done              (div_done),
        .quotient_q8_8     (div_quotient_q8_8)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= S_IDLE;
            idx            <= '0;
            sum_acc_q6_26  <= '0;
            done           <= 1'b0;
            div_start      <= 1'b0;
            entropy_out_q8_8      <= '0;
            confidence_out_q0_16  <= '0;
        end else begin
            done      <= 1'b0;
            div_start <= 1'b0;
            unique case (state)
                S_IDLE: begin
                    if (start) begin
                        idx           <= '0;
                        sum_acc_q6_26 <= '0;
                        state         <= S_ACCUM;
                    end
                end

                S_ACCUM: begin
                    sum_acc_q6_26 <= sum_acc_q6_26 + {8'b0, term_q6_26};
                    if (idx == NUM_CLASSES-1)
                        state <= S_RESCALE;
                    else
                        idx <= idx + 1'b1;
                end

                S_RESCALE: begin
                    sum_bits_q6_8 <= sum_acc_q6_26[39:18];
                    state <= S_TO_NATS;
                end

                S_TO_NATS: begin
                    automatic logic [37:0] nats_wide;
                    nats_wide = sum_bits_q6_8 * LN2_Q1_15;
                    h_nats_q8_8 <= $signed(nats_wide[30:15]);
                    state <= S_DIVSTART;
                end

                S_DIVSTART: begin
                    div_start <= 1'b1;
                    state <= S_DIVWAIT;
                end

                S_DIVWAIT: begin
                    if (div_done) begin
                        automatic logic signed [16:0] conf_q8_8;
                        conf_q8_8 = 17'sd256 - $signed({div_quotient_q8_8[15], div_quotient_q8_8});
                        entropy_out_q8_8 <= h_nats_q8_8;
                        if (conf_q8_8 < 0)
                            confidence_out_q0_16 <= 16'd0;
                        else if (conf_q8_8 > 17'sd256)
                            confidence_out_q0_16 <= 16'hFFFF;
                        else
                            confidence_out_q0_16 <= 16'(conf_q8_8) << 8;
                        state <= S_DONE;
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
endmodule
