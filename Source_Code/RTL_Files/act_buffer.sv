import sentinel_pkg::*;

module act_buffer #(
    parameter int DEPTH = 65536,
    parameter int ADDR_W = $clog2(DEPTH)
) (
    input  logic                     clk,
    input  logic                     bank_swap,

    input  logic                     wr_en,
    input  logic [ADDR_W-1:0]        wr_addr,
    input  logic signed [ACT_W-1:0]  wr_data,

    input  logic                     rd_en,
    input  logic [ADDR_W-1:0]        rd_addr,
    output logic signed [ACT_W-1:0]  rd_data
);
    (* ram_style = "block" *) logic signed [ACT_W-1:0] bank0 [DEPTH];
    (* ram_style = "block" *) logic signed [ACT_W-1:0] bank1 [DEPTH];
    logic write_bank_sel;

    always_ff @(posedge clk) begin
        if (bank_swap)
            write_bank_sel <= ~write_bank_sel;
    end

    always_ff @(posedge clk) begin
        if (wr_en) begin
            if (write_bank_sel) bank1[wr_addr] <= wr_data;
            else                bank0[wr_addr] <= wr_data;
        end
        if (rd_en) begin
            rd_data <= write_bank_sel ? bank0[rd_addr] : bank1[rd_addr];
        end
    end
endmodule
