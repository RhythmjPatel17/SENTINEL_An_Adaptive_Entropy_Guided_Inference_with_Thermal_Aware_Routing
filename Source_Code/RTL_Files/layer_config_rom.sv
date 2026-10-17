import sentinel_pkg::*;

module layer_config_rom #(
    parameter int MAX_LAYERS = 32,
    parameter int ADDR_W = $clog2(MAX_LAYERS)
) (
    input  logic                clk,
    input  logic                rst_n,

    input  logic                wr_en,
    input  logic [ADDR_W-1:0]   wr_addr,
    input  layer_desc_t         wr_data,

    input  logic [ADDR_W-1:0]   rd_addr,
    output layer_desc_t         rd_data,

    input  logic [ADDR_W:0]     num_layers_in,
    output logic [ADDR_W:0]     num_layers_out
);
    (* ram_style = "distributed" *) layer_desc_t table_mem [MAX_LAYERS];
    logic [ADDR_W:0] num_layers_reg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            num_layers_reg <= '0;
        end else if (wr_en) begin
            table_mem[wr_addr] <= wr_data;
            num_layers_reg     <= num_layers_in;
        end
    end

    assign rd_data        = table_mem[rd_addr];
    assign num_layers_out = num_layers_reg;
endmodule
