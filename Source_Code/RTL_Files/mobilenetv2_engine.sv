import sentinel_pkg::*;

module mobilenetv2_engine #(
    parameter int MAX_LAYERS = 32,
    parameter int IMG_DEPTH  = 224*224
) (
    input  logic                     clk,
    input  logic                     rst_n,

    input  logic signed [WGT_W-1:0]  s_axis_wdata,
    input  logic                     s_axis_wvalid,
    output logic                     s_axis_wready,
    input  logic                     s_axis_wlast,
    input  logic [$clog2(MAX_LAYERS)-1:0] cfg_wr_addr,
    input  logic                     cfg_wr_en,
    input  layer_desc_t              cfg_wr_data,
    input  logic [$clog2(MAX_LAYERS):0]   num_layers_in,

    input  logic                     img_px_valid,
    input  logic signed [ACT_W-1:0]  img_px_in [NUM_PE],

    input  logic                     start,
    output logic                     done,

    output logic                     probs_valid,
    output logic              [15:0] probs_out_q0_16 [NUM_CLASSES]
);
    logic [$clog2(MAX_LAYERS)-1:0] cfg_rd_addr;
    layer_desc_t cfg_rd_data;
    logic [$clog2(MAX_LAYERS):0]  num_layers_reg;

    layer_config_rom #(.MAX_LAYERS(MAX_LAYERS)) u_cfg_rom (
        .clk(clk), .rst_n(rst_n),
        .wr_en(cfg_wr_en), .wr_addr(cfg_wr_addr), .wr_data(cfg_wr_data),
        .rd_addr(cfg_rd_addr), .rd_data(cfg_rd_data),
        .num_layers_in(num_layers_in), .num_layers_out(num_layers_reg)
    );

    logic signed [WGT_W-1:0] wgt_rd_data [NUM_PE];
    logic [15:0] wgt_addr_perlane [NUM_PE];

    weight_buffer #(.DEPTH(65536)) u_wgt_buf (
        .clk(clk), .rst_n(rst_n),
        .s_axis_wdata(s_axis_wdata), .s_axis_wvalid(s_axis_wvalid),
        .s_axis_wready(s_axis_wready), .s_axis_wlast(s_axis_wlast),
        .load_done(), .rd_addr(wgt_addr_perlane), .rd_data(wgt_rd_data)
    );

    logic dw_start, dw_done, pw_start, pw_done, se_start, se_done;
    logic act_bank_swap;
    logic [16:0] pixel_addr;
    logic [9:0]  chan_group;

    layer_sequencer #(.MAX_LAYERS(MAX_LAYERS)) u_seq (
        .clk(clk), .rst_n(rst_n),
        .network_start(start), .num_layers(num_layers_reg), .network_done(done),
        .cfg_rd_addr(cfg_rd_addr), .cfg_rd_data(cfg_rd_data),
        .dw_start(dw_start), .dw_done(dw_done),
        .pw_start(pw_start), .pw_done(pw_done),
        .se_start(se_start), .se_done(se_done),

        .pixel_addr(pixel_addr), .chan_group(chan_group),
        .act_bank_swap(act_bank_swap)
    );

    act_buffer #(.DEPTH(IMG_DEPTH)) u_act_buf (
        .clk(clk), .bank_swap(act_bank_swap),
        .wr_en(1'b0), .wr_addr('0), .wr_data('0),
        .rd_en(1'b0), .rd_addr('0), .rd_data()
    );

    logic signed [ACT_W-1:0] dw_pixel_out [NUM_PE];
    logic signed [ACT_W-1:0] pw_pixel_out [NUM_PE];

    depthwise_conv_unit u_dw (
        .clk(clk), .rst_n(rst_n), .start(dw_start),
        .kernel(cfg_rd_data.kernel),
        .win_in('{default: '{default: '{default: '0}}}),
        .wgt_in('{default: '{default: '{default: '0}}}),
        .act_sel(cfg_rd_data.act),
        .requant_mult(cfg_rd_data.requant_mult), .requant_shift(cfg_rd_data.requant_shift),
        .done(dw_done), .pixel_out(dw_pixel_out)
    );

    pointwise_conv_unit u_pw (
        .clk(clk), .rst_n(rst_n), .start(pw_start),
        .in_ch(cfg_rd_data.in_ch),
        .act_stream_in('0), .act_stream_valid(1'b0),
        .wgt_stream_in(wgt_rd_data),
        .act_sel(cfg_rd_data.act),
        .requant_mult(cfg_rd_data.requant_mult), .requant_shift(cfg_rd_data.requant_shift),
        .use_residual(cfg_rd_data.use_residual), .residual_in('{default: '0}),
        .done(pw_done), .pixel_out(pw_pixel_out)
    );

    logic signed [ACT_W-1:0] final_logits [NUM_CLASSES];
    logic fc_layer_done;
    assign fc_layer_done = pw_done && (cfg_rd_data.ltype == LT_FC);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < NUM_CLASSES; i++) final_logits[i] <= '0;
        end else if (fc_layer_done) begin
            for (int i = 0; i < NUM_CLASSES; i++) final_logits[i] <= pw_pixel_out[i];
        end
    end

    softmax_stage u_softmax (
        .clk(clk), .rst_n(rst_n),
        .start(fc_layer_done),
        .logits_in(final_logits),
        .done(probs_valid),
        .probs_out_q0_16(probs_out_q0_16)
    );
endmodule
