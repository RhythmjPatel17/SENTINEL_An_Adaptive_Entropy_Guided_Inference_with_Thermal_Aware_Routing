import sentinel_pkg::*;

module softmax_stage #(
    parameter logic [15:0] SOFTMAX_SCALE_Q1_15 = 16'd11827
) (
    input  logic                     clk,
    input  logic                     rst_n,
    input  logic                     start,
    input  logic signed [ACT_W-1:0]  logits_in [NUM_CLASSES],
    output logic                     done,
    output logic              [15:0] probs_out_q0_16 [NUM_CLASSES]
);
    logic signed [ACT_W-1:0] max_logit;
    always_comb begin
        max_logit = logits_in[0];
        for (int i = 1; i < NUM_CLASSES; i++)
            if (logits_in[i] > max_logit) max_logit = logits_in[i];
    end

    typedef enum logic [2:0] {
        S_IDLE, S_EXP_SET, S_EXP_CAPTURE, S_DIVSTART, S_DIVWAIT, S_DONE
    } state_t;
    state_t state;

    logic [2:0] idx;
    logic [15:0] exp_vals [NUM_CLASSES];
    logic [21:0] sum_acc;
    logic signed [15:0] y_q6_10;
    logic [15:0] exp_result;

    exp2_approx u_exp (.y_q6_10(y_q6_10), .exp2_out_q0_16(exp_result));

    logic div_start, div_done;
    logic signed [15:0] div_quotient_q8_8;
    logic [15:0] sum_as_denom_q8_8;

    assign sum_as_denom_q8_8 = (sum_acc[21:6] > 16'hFFFF) ? 16'hFFFF : sum_acc[21:6];

    newton_raphson_divider u_div (
        .clk(clk), .rst_n(rst_n), .start(div_start),
        .numerator_q8_8({1'b0, exp_vals[idx][14:8]}),
        .denominator_q8_8(sum_as_denom_q8_8),
        .done(div_done), .quotient_q8_8(div_quotient_q8_8)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE; idx <= '0; sum_acc <= '0; done <= 1'b0;
            div_start <= 1'b0; y_q6_10 <= '0;
            for (int i = 0; i < NUM_CLASSES; i++) probs_out_q0_16[i] <= '0;
        end else begin
            done <= 1'b0;
            div_start <= 1'b0;
            unique case (state)
                S_IDLE: begin
                    if (start) begin
                        idx <= '0; sum_acc <= '0;
                        state <= S_EXP_SET;
                    end
                end

                S_EXP_SET: begin
                    automatic logic signed [8:0] logit_diff;
                    automatic logic signed [24:0] y_wide;
                    logit_diff = {logits_in[idx][7], logits_in[idx]} - {max_logit[7], max_logit};
                    y_wide = $signed({{7{logit_diff[8]}}, logit_diff}) * $signed({1'b0, SOFTMAX_SCALE_Q1_15});
                    y_q6_10 <= y_wide[20:5];
                    state <= S_EXP_CAPTURE;
                end

                S_EXP_CAPTURE: begin
                    exp_vals[idx] <= exp_result;
                    sum_acc       <= sum_acc + exp_result;
                    if (idx == NUM_CLASSES-1) begin
                        idx   <= '0;
                        state <= S_DIVSTART;
                    end else begin
                        idx   <= idx + 1'b1;
                        state <= S_EXP_SET;
                    end
                end

                S_DIVSTART: begin
                    div_start <= 1'b1;
                    state <= S_DIVWAIT;
                end

                S_DIVWAIT: begin
                    if (div_done) begin
                        probs_out_q0_16[idx] <= {div_quotient_q8_8, 8'b0};
                        if (idx == NUM_CLASSES-1)
                            state <= S_DONE;
                        else begin
                            idx <= idx + 1'b1;
                            state <= S_DIVSTART;
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
endmodule
