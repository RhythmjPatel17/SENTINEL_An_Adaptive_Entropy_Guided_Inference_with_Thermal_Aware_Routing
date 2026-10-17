import sentinel_pkg::*;

module thermal_governor_unit (
    input  logic                clk,
    input  logic                rst_n,
    input  logic                start,
    input  logic signed [15:0]  t_junction_q8_8,
    output logic                done,
    output logic         [15:0] threshold_out_q0_16
);
    localparam logic [15:0] DIV_125_Q8_8 = 16'd32000;

    typedef enum logic [1:0] {S_IDLE, S_DIVSTART, S_DIVWAIT, S_DONE} state_t;
    state_t state;

    logic signed [15:0] delta_t_q8_8;
    logic                div_start, div_done;
    logic signed [15:0] alpha_delta_q8_8;

    assign delta_t_q8_8 = t_junction_q8_8 - TCRIT_Q8_8;

    newton_raphson_divider u_div (
        .clk               (clk),
        .rst_n             (rst_n),
        .start             (div_start),
        .numerator_q8_8    (delta_t_q8_8),
        .denominator_q8_8  (DIV_125_Q8_8),
        .done              (div_done),
        .quotient_q8_8     (alpha_delta_q8_8)
    );

    logic signed [23:0] delta_tau_q0_16;
    logic signed [23:0] tau_raw_q0_16;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            done  <= 1'b0;
            div_start <= 1'b0;
            threshold_out_q0_16 <= TAU_BASE_Q0_16;
        end else begin
            done <= 1'b0;
            div_start <= 1'b0;
            unique case (state)
                S_IDLE: if (start) begin
                    div_start <= 1'b1;
                    state <= S_DIVWAIT;
                end

                S_DIVWAIT: if (div_done) begin
                    delta_tau_q0_16 = $signed({{8{alpha_delta_q8_8[15]}}, alpha_delta_q8_8}) <<< 8;
                    tau_raw_q0_16   = $signed({8'b0, TAU_BASE_Q0_16}) - delta_tau_q0_16;

                    if (tau_raw_q0_16 < $signed({8'b0, TAU_MIN_Q0_16}))
                        threshold_out_q0_16 <= TAU_MIN_Q0_16;
                    else if (tau_raw_q0_16 > 24'sd65535)
                        threshold_out_q0_16 <= 16'hFFFF;
                    else
                        threshold_out_q0_16 <= tau_raw_q0_16[15:0];

                    state <= S_DONE;
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
