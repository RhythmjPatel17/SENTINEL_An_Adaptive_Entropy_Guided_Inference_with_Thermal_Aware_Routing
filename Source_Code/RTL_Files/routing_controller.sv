import sentinel_pkg::*;

module routing_controller (
    input  logic                clk,
    input  logic                rst_n,

    input  logic                start,
    input  logic [15:0]         prob_in [NUM_CLASSES],
    input  logic signed [15:0]  t_junction_q8_8,

    output logic                done,
    output logic                route_to_m2,
    output logic signed [15:0]  entropy_out_q8_8,
    output logic [15:0]         confidence_out_q0_16,
    output logic [15:0]         threshold_out_q0_16
);
    logic entropy_done, thermal_done;

    thermal_governor_unit u_thermal (
        .clk                  (clk),
        .rst_n                (rst_n),
        .start                (start),
        .t_junction_q8_8      (t_junction_q8_8),
        .done                 (thermal_done),
        .threshold_out_q0_16  (threshold_out_q0_16)
    );

    entropy_confidence_unit u_entropy (
        .clk                    (clk),
        .rst_n                  (rst_n),
        .start                  (start),
        .prob_in                (prob_in),
        .done                   (entropy_done),
        .entropy_out_q8_8       (entropy_out_q8_8),
        .confidence_out_q0_16   (confidence_out_q0_16)
    );

    typedef enum logic [1:0] {S_IDLE, S_WAIT, S_DONE} state_t;
    state_t state;
    logic entropy_seen, thermal_seen;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            done <= 1'b0;
            route_to_m2 <= 1'b0;
            entropy_seen <= 1'b0;
            thermal_seen <= 1'b0;
        end else begin
            done <= 1'b0;
            unique case (state)
                S_IDLE: begin
                    if (start) begin
                        entropy_seen <= 1'b0;
                        thermal_seen <= 1'b0;
                        state <= S_WAIT;
                    end
                end
                S_WAIT: begin
                    if (entropy_done) entropy_seen <= 1'b1;
                    if (thermal_done) thermal_seen <= 1'b1;
                    if ((entropy_seen || entropy_done) && (thermal_seen || thermal_done))
                        state <= S_DONE;
                end
                S_DONE: begin
                    route_to_m2 <= (confidence_out_q0_16 < threshold_out_q0_16);
                    done  <= 1'b1;
                    state <= S_IDLE;
                end
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
