import sentinel_pkg::*;

module line_buffer #(
    parameter int MAX_W = 224
) (
    input  logic                    clk,
    input  logic                    rst_n,
    input  logic [2:0]              kernel,
    input  logic [10:0]             img_width,

    input  logic                    px_valid,
    input  logic signed [ACT_W-1:0] px_in [NUM_PE],

    output logic                    win_valid,
    output logic signed [ACT_W-1:0] win_out [NUM_PE][MAX_KSIZE][MAX_KSIZE]
);
    (* ram_style = "block" *) logic signed [ACT_W-1:0] row_fifo [MAX_KSIZE-1][MAX_W][NUM_PE];
    logic [10:0] col_ptr;
    logic [2:0]  row_fill_count;
    logic signed [ACT_W-1:0] window [NUM_PE][MAX_KSIZE][MAX_KSIZE];

    integer c, r, k;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            col_ptr        <= '0;
            row_fill_count <= '0;
            win_valid      <= 1'b0;
        end else if (px_valid) begin
            for (c = 0; c < NUM_PE; c++) begin
                for (r = 0; r < MAX_KSIZE; r++) begin
                    for (k = 0; k < MAX_KSIZE-1; k++)
                        window[c][r][k] <= window[c][r][k+1];
                end
                for (r = 0; r < MAX_KSIZE-1; r++)
                    window[c][r][MAX_KSIZE-1] <= row_fifo[r][col_ptr][c];
                window[c][kernel-1][MAX_KSIZE-1] <= px_in[c];

                row_fifo[0][col_ptr][c] <= px_in[c];
                for (r = 1; r < MAX_KSIZE-1; r++)
                    row_fifo[r][col_ptr][c] <= row_fifo[r-1][col_ptr][c];
            end

            col_ptr <= (col_ptr == img_width - 1) ? '0 : col_ptr + 1'b1;
            if (col_ptr == img_width - 1 && row_fill_count < kernel - 1)
                row_fill_count <= row_fill_count + 1'b1;

            win_valid <= (row_fill_count >= kernel - 1) && (col_ptr >= kernel - 1);
        end else begin
            win_valid <= 1'b0;
        end
    end

    assign win_out = window;
endmodule
