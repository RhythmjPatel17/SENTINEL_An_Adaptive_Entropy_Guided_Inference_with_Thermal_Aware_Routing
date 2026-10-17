import sentinel_pkg::*;

module se_block (
    input  logic                    clk,
    input  logic                    rst_n,

    input  logic                    start,
    input  logic [10:0]             hw_pixels,
    input  logic [9:0]              channels,

    input  logic                    px_valid,
    input  logic signed [ACT_W-1:0] px_in [NUM_PE],

    input  logic signed [WGT_W-1:0] fc1_wgt [NUM_PE],
    input  logic signed [WGT_W-1:0] fc2_wgt [NUM_PE],
    input  logic [15:0]             requant_mult,
    input  logic [4:0]              requant_shift,

    output logic                    done,
    output logic signed [ACT_W-1:0] scale_out [NUM_PE]
);
    logic signed [ACC_W-1:0] gap_acc [NUM_PE];
    logic [10:0]             px_count;
    logic signed [ACT_W-1:0] gap_out [NUM_PE];

    typedef enum logic [2:0] {S_IDLE, S_POOL, S_FC1, S_FC2, S_DONE} state_t;
    state_t state;

    integer c;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE; px_count <= '0;
            for (c = 0; c < NUM_PE; c++) gap_acc[c] <= '0;
            done <= 1'b0;
        end else begin
            done <= 1'b0;
            unique case (state)
                S_IDLE: begin
                    if (start) begin
                        px_count <= '0;
                        for (c = 0; c < NUM_PE; c++) gap_acc[c] <= '0;
                        state <= S_POOL;
                    end
                end
                S_POOL: begin
                    if (px_valid) begin
                        for (c = 0; c < NUM_PE; c++)
                            gap_acc[c] <= gap_acc[c] + ACC_W'(px_in[c]);
                        if (px_count == hw_pixels - 1)
                            state <= S_FC1;
                        else
                            px_count <= px_count + 1'b1;
                    end
                end
                S_FC1: state <= S_FC2;
                S_FC2: state <= S_DONE;
                S_DONE: begin
                    done  <= 1'b1;
                    state <= S_IDLE;
                end
                default: state <= S_IDLE;
            endcase
        end
    end

    genvar g;
    generate
        for (g = 0; g < NUM_PE; g++) begin : g_gap
            logic signed [47:0] scaled;
            assign scaled = gap_acc[g] * $signed({1'b0, requant_mult});
            assign gap_out[g] = (scaled >>> requant_shift) > 127 ? 8'sd127 :
                                 (scaled >>> requant_shift) < -128 ? -8'sd128 :
                                 (scaled >>> requant_shift);
        end
    endgenerate

    assign scale_out = gap_out;
endmodule
