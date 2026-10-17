import sentinel_pkg::*;

module layer_sequencer #(
    parameter int MAX_LAYERS = 32,
    parameter int ADDR_W = $clog2(MAX_LAYERS)
) (
    input  logic                clk,
    input  logic                rst_n,

    input  logic                network_start,
    input  logic [ADDR_W:0]     num_layers,
    output logic                network_done,

    output logic [ADDR_W-1:0]   cfg_rd_addr,
    input  layer_desc_t         cfg_rd_data,

    output logic                dw_start,
    input  logic                dw_done,
    output logic                pw_start,
    input  logic                pw_done,
    output logic                se_start,
    input  logic                se_done,

    output logic [16:0]         pixel_addr,
    output logic [9:0]          chan_group,

    output logic                act_bank_swap
);
    typedef enum logic [2:0] {
        S_IDLE, S_LOAD_LAYER, S_DISPATCH, S_WAIT_UNIT,
        S_NEXT_CHAN, S_NEXT_PIXEL, S_NEXT_LAYER, S_DONE
    } state_t;
    state_t state;

    logic [ADDR_W-1:0] layer_idx;
    logic [16:0]        pixel_cnt;
    logic [9:0]          chan_cnt;
    logic [16:0]         total_pixels;
    logic [9:0]           total_chan_groups;

    layer_desc_t cur_layer;
    assign cfg_rd_addr = layer_idx;
    assign cur_layer   = cfg_rd_data;

    assign pixel_addr = pixel_cnt;
    assign chan_group = chan_cnt;

    always_comb begin
        total_pixels      = ((cur_layer.in_h / cur_layer.stride) *
                              (cur_layer.in_w / cur_layer.stride));
        total_chan_groups = (cur_layer.out_ch + NUM_PE - 1) / NUM_PE;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            layer_idx <= '0; pixel_cnt <= '0; chan_cnt <= '0;
            network_done <= 1'b0; act_bank_swap <= 1'b0;
            dw_start <= 1'b0; pw_start <= 1'b0; se_start <= 1'b0;
        end else begin
            dw_start <= 1'b0; pw_start <= 1'b0; se_start <= 1'b0;
            act_bank_swap <= 1'b0; network_done <= 1'b0;

            unique case (state)
                S_IDLE: begin
                    if (network_start) begin
                        layer_idx <= '0;
                        state <= S_LOAD_LAYER;
                    end
                end

                S_LOAD_LAYER: begin
                    pixel_cnt <= '0;
                    chan_cnt  <= '0;
                    state <= S_DISPATCH;
                end

                S_DISPATCH: begin
                    unique case (cur_layer.ltype)
                        LT_DEPTHWISE:                          dw_start <= 1'b1;
                        LT_POINTWISE, LT_STANDARD3x3, LT_FC:    pw_start <= 1'b1;
                        LT_SE, LT_AVGPOOL:                      se_start <= 1'b1;
                        default: ;
                    endcase
                    state <= S_WAIT_UNIT;
                end

                S_WAIT_UNIT: begin
                    if (dw_done || pw_done || se_done)
                        state <= S_NEXT_CHAN;
                end

                S_NEXT_CHAN: begin
                    if (chan_cnt == total_chan_groups - 1) begin
                        chan_cnt <= '0;
                        state <= S_NEXT_PIXEL;
                    end else begin
                        chan_cnt <= chan_cnt + 1'b1;
                        state <= S_DISPATCH;
                    end
                end

                S_NEXT_PIXEL: begin
                    if (pixel_cnt == total_pixels - 1) begin
                        state <= S_NEXT_LAYER;
                    end else begin
                        pixel_cnt <= pixel_cnt + 1'b1;
                        state <= S_DISPATCH;
                    end
                end

                S_NEXT_LAYER: begin
                    act_bank_swap <= 1'b1;
                    if (layer_idx == num_layers - 1) begin
                        state <= S_DONE;
                    end else begin
                        layer_idx <= layer_idx + 1'b1;
                        state <= S_LOAD_LAYER;
                    end
                end

                S_DONE: begin
                    network_done <= 1'b1;
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
