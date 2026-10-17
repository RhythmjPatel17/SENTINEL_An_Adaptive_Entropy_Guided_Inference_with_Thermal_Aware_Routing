import sentinel_pkg::*;

module newton_raphson_divider #(
    parameter int N_ITER = 4
) (
    input  logic                     clk,
    input  logic                     rst_n,
    input  logic                     start,
    input  logic signed [15:0]       numerator_q8_8,
    input  logic        [15:0]       denominator_q8_8,
    output logic                     done,
    output logic signed [15:0]       quotient_q8_8
);
    logic [3:0]  msb_pos;
    logic        lod_valid;
    logic [15:0] d_shifted;
    logic [15:0] x_reg;

    typedef enum logic [2:0] {S_IDLE, S_NORM, S_SEED, S_ITER, S_RESCALE, S_MUL, S_DONE} state_t;
    state_t state;
    logic [2:0] iter_cnt;
    logic signed [15:0] numerator_reg;
    logic [4:0] msb_pos_reg;
    logic [15:0] recip_final;

    always_comb begin
        lod_valid = |denominator_q8_8;
        msb_pos = 4'd0;
        for (int b = 15; b >= 0; b--)
            if (denominator_q8_8[b]) begin
                msb_pos = b[3:0];
                break;
            end
    end

    logic [31:0] mul_tmp;
    logic [16:0] product_q1_15;
    logic [16:0] two_minus_product;
    logic [31:0] mul_tmp2;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            done  <= 1'b0;
            quotient_q8_8 <= '0;
        end else begin
            done <= 1'b0;
            unique case (state)
                S_IDLE: begin
                    if (start) begin
                        numerator_reg <= numerator_q8_8;
                        state <= S_NORM;
                    end
                end

                S_NORM: begin
                    d_shifted   <= denominator_q8_8 << (4'd15 - msb_pos);
                    msb_pos_reg <= {1'b0, msb_pos};
                    state <= S_SEED;
                end

                S_SEED: begin
                    automatic logic [16:0] seed_wide;
                    seed_wide = 17'd49152 - {1'b0, d_shifted};
                    x_reg <= seed_wide[15:0];
                    iter_cnt <= '0;
                    state <= S_ITER;
                end

                S_ITER: begin
                    mul_tmp        = d_shifted * x_reg;
                    product_q1_15  = mul_tmp[31:16];
                    two_minus_product = 17'd65536 - product_q1_15;
                    mul_tmp2       = x_reg * two_minus_product[15:0];
                    x_reg         <= mul_tmp2[30:15];

                    if (iter_cnt == N_ITER-1)
                        state <= S_RESCALE;
                    else
                        iter_cnt <= iter_cnt + 1'b1;
                end

                S_RESCALE: begin
                    recip_final <= x_reg >> msb_pos_reg;
                    state <= S_MUL;
                end

                S_MUL: begin
                    automatic logic signed [32:0] quot_wide;
                    quot_wide = $signed(numerator_reg) * $signed({1'b0, recip_final});
                    quotient_q8_8 <= quot_wide[23:8];
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
