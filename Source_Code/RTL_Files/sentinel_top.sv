import sentinel_pkg::*;

module sentinel_top #(
    parameter int MAX_LAYERS = 32,
    parameter int IMG_HW     = 224
) (
    input  logic clk,
    input  logic rst_n,

    input  logic signed [WGT_W-1:0]        v3_wdata,
    input  logic                           v3_wvalid,
    output logic                            v3_wready,
    input  logic                           v3_wlast,
    input  logic [$clog2(MAX_LAYERS)-1:0]  v3_cfg_addr,
    input  logic                           v3_cfg_wen,
    input  layer_desc_t                    v3_cfg_wdata,
    input  logic [$clog2(MAX_LAYERS):0]    v3_num_layers,

    input  logic signed [WGT_W-1:0]        v2_wdata,
    input  logic                           v2_wvalid,
    output logic                            v2_wready,
    input  logic                           v2_wlast,
    input  logic [$clog2(MAX_LAYERS)-1:0]  v2_cfg_addr,
    input  logic                           v2_cfg_wen,
    layer_desc_t                           v2_cfg_wdata,
    input  logic [$clog2(MAX_LAYERS):0]    v2_num_layers,

    input  logic [7:0] s_axis_img_tdata,
    input  logic        s_axis_img_tvalid,
    output logic         s_axis_img_tready,
    input  logic        s_axis_img_tlast,

    input  logic [5:0]  S_AXI_AWADDR,
    input  logic        S_AXI_AWVALID,
    output logic         S_AXI_AWREADY,
    input  logic [31:0] S_AXI_WDATA,
    input  logic [3:0]  S_AXI_WSTRB,
    input  logic        S_AXI_WVALID,
    output logic         S_AXI_WREADY,
    output logic [1:0]   S_AXI_BRESP,
    output logic         S_AXI_BVALID,
    input  logic        S_AXI_BREADY,
    input  logic [5:0]  S_AXI_ARADDR,
    input  logic        S_AXI_ARVALID,
    output logic         S_AXI_ARREADY,
    output logic [31:0]  S_AXI_RDATA,
    output logic [1:0]   S_AXI_RRESP,
    output logic         S_AXI_RVALID,
    input  logic        S_AXI_RREADY
);

    logic v3_start, v3_done, v3_img_px_valid, v3_probs_valid;
    logic signed [ACT_W-1:0] v3_img_px_in [NUM_PE];
    logic [15:0] v3_probs_q0_16 [NUM_CLASSES];

    logic v2_start, v2_done, v2_img_px_valid, v2_probs_valid;
    logic signed [ACT_W-1:0] v2_img_px_in [NUM_PE];
    logic [15:0] v2_probs_q0_16 [NUM_CLASSES];

    logic route_start, route_done, route_to_m2;
    logic signed [15:0] route_entropy_q8_8;
    logic [15:0] route_confidence_q0_16, route_threshold_q0_16;
    logic signed [15:0] reg_temp_for_routing_q8_8;

    mobilenetv3_engine #(.MAX_LAYERS(MAX_LAYERS), .IMG_DEPTH(IMG_HW*IMG_HW)) u_v3 (
        .clk(clk), .rst_n(rst_n),
        .s_axis_wdata(v3_wdata), .s_axis_wvalid(v3_wvalid), .s_axis_wready(v3_wready), .s_axis_wlast(v3_wlast),
        .cfg_wr_addr(v3_cfg_addr), .cfg_wr_en(v3_cfg_wen), .cfg_wr_data(v3_cfg_wdata), .num_layers_in(v3_num_layers),
        .img_px_valid(v3_img_px_valid), .img_px_in(v3_img_px_in),
        .start(v3_start), .done(v3_done),
        .probs_valid(v3_probs_valid), .probs_out_q0_16(v3_probs_q0_16)
    );

    mobilenetv2_engine #(.MAX_LAYERS(MAX_LAYERS), .IMG_DEPTH(IMG_HW*IMG_HW)) u_v2 (
        .clk(clk), .rst_n(rst_n),
        .s_axis_wdata(v2_wdata), .s_axis_wvalid(v2_wvalid), .s_axis_wready(v2_wready), .s_axis_wlast(v2_wlast),
        .cfg_wr_addr(v2_cfg_addr), .cfg_wr_en(v2_cfg_wen), .cfg_wr_data(v2_cfg_wdata), .num_layers_in(v2_num_layers),
        .img_px_valid(v2_img_px_valid), .img_px_in(v2_img_px_in),
        .start(v2_start), .done(v2_done),
        .probs_valid(v2_probs_valid), .probs_out_q0_16(v2_probs_q0_16)
    );

    routing_controller u_routing (
        .clk(clk), .rst_n(rst_n),
        .start(route_start),
        .prob_in(v3_probs_q0_16),
        .t_junction_q8_8(reg_temp_for_routing_q8_8),
        .done(route_done), .route_to_m2(route_to_m2),
        .entropy_out_q8_8(route_entropy_q8_8),
        .confidence_out_q0_16(route_confidence_q0_16),
        .threshold_out_q0_16(route_threshold_q0_16)
    );

    ctrl_fsm_axi_dma #(.IMG_HW(IMG_HW)) u_ctrl (
        .clk(clk), .rst_n(rst_n),
        .s_axis_img_tdata(s_axis_img_tdata), .s_axis_img_tvalid(s_axis_img_tvalid),
        .s_axis_img_tready(s_axis_img_tready), .s_axis_img_tlast(s_axis_img_tlast),
        .S_AXI_AWADDR(S_AXI_AWADDR), .S_AXI_AWVALID(S_AXI_AWVALID), .S_AXI_AWREADY(S_AXI_AWREADY),
        .S_AXI_WDATA(S_AXI_WDATA), .S_AXI_WSTRB(S_AXI_WSTRB), .S_AXI_WVALID(S_AXI_WVALID), .S_AXI_WREADY(S_AXI_WREADY),
        .S_AXI_BRESP(S_AXI_BRESP), .S_AXI_BVALID(S_AXI_BVALID), .S_AXI_BREADY(S_AXI_BREADY),
        .S_AXI_ARADDR(S_AXI_ARADDR), .S_AXI_ARVALID(S_AXI_ARVALID), .S_AXI_ARREADY(S_AXI_ARREADY),
        .S_AXI_RDATA(S_AXI_RDATA), .S_AXI_RRESP(S_AXI_RRESP), .S_AXI_RVALID(S_AXI_RVALID), .S_AXI_RREADY(S_AXI_RREADY),
        .v3_start(v3_start), .v3_done(v3_done),
        .v3_img_px_valid(v3_img_px_valid), .v3_img_px_in(v3_img_px_in),
        .v3_probs_valid(v3_probs_valid), .v3_probs_q0_16(v3_probs_q0_16),
        .v2_start(v2_start), .v2_done(v2_done),
        .v2_img_px_valid(v2_img_px_valid), .v2_img_px_in(v2_img_px_in),
        .v2_probs_valid(v2_probs_valid), .v2_probs_q0_16(v2_probs_q0_16),
        .route_start(route_start), .route_done(route_done), .route_to_m2(route_to_m2),
        .route_entropy_q8_8(route_entropy_q8_8),
        .route_confidence_q0_16(route_confidence_q0_16),
        .route_threshold_q0_16(route_threshold_q0_16)
    );

    assign reg_temp_for_routing_q8_8 = u_ctrl.reg_temp_q8_8;
endmodule
