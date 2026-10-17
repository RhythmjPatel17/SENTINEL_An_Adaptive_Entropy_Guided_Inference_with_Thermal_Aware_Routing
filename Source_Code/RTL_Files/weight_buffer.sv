import sentinel_pkg::*;

module weight_buffer #(
    parameter int DEPTH = 65536,
    parameter int ADDR_W = $clog2(DEPTH)
) (
    input  logic                     clk,
    input  logic                     rst_n,

    input  logic signed [WGT_W-1:0]  s_axis_wdata,
    input  logic                     s_axis_wvalid,
    output logic                     s_axis_wready,
    input  logic                     s_axis_wlast,

    output logic                     load_done,

    input  logic [ADDR_W-1:0]        rd_addr [NUM_PE],
    output logic signed [WGT_W-1:0]  rd_data [NUM_PE]
);
    (* ram_style = "block" *) logic signed [WGT_W-1:0] mem [DEPTH];
    logic [ADDR_W-1:0] wr_ptr;

    assign s_axis_wready = 1'b1;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr    <= '0;
            load_done <= 1'b0;
        end else begin
            load_done <= 1'b0;
            if (s_axis_wvalid && s_axis_wready) begin
                mem[wr_ptr] <= s_axis_wdata;
                if (s_axis_wlast) begin
                    wr_ptr    <= '0;
                    load_done <= 1'b1;
                end else begin
                    wr_ptr <= wr_ptr + 1'b1;
                end
            end
        end
    end

    genvar i;
    generate
        for (i = 0; i < NUM_PE; i++) begin : g_rd
            assign rd_data[i] = mem[rd_addr[i]];
        end
    endgenerate
endmodule
