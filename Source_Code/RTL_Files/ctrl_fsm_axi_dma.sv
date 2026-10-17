import sentinel_pkg::*;

module ctrl_fsm_axi_dma #(
    parameter int IMG_HW = 224,
    parameter int C_S_AXI_DATA_WIDTH = 32,
    parameter int C_S_AXI_ADDR_WIDTH = 6
) (
    input  logic clk,
    input  logic rst_n,

    input  logic [7:0]  s_axis_img_tdata,
    input  logic        s_axis_img_tvalid,
    output logic         s_axis_img_tready,
    input  logic        s_axis_img_tlast,

    input  logic [C_S_AXI_ADDR_WIDTH-1:0]     S_AXI_AWADDR,
    input  logic                              S_AXI_AWVALID,
    output logic                              S_AXI_AWREADY,
    input  logic [C_S_AXI_DATA_WIDTH-1:0]     S_AXI_WDATA,
    input  logic [(C_S_AXI_DATA_WIDTH/8)-1:0] S_AXI_WSTRB,
    input  logic                              S_AXI_WVALID,
    output logic                              S_AXI_WREADY,
    output logic [1:0]                        S_AXI_BRESP,
    output logic                              S_AXI_BVALID,
    input  logic                              S_AXI_BREADY,
    input  logic [C_S_AXI_ADDR_WIDTH-1:0]     S_AXI_ARADDR,
    input  logic                              S_AXI_ARVALID,
    output logic                              S_AXI_ARREADY,
    output logic [C_S_AXI_DATA_WIDTH-1:0]     S_AXI_RDATA,
    output logic [1:0]                        S_AXI_RRESP,
    output logic                              S_AXI_RVALID,
    input  logic                              S_AXI_RREADY,

    output logic                     v3_start,
    input  logic                     v3_done,
    output logic                     v3_img_px_valid,
    output logic signed [ACT_W-1:0]  v3_img_px_in [NUM_PE],
    input  logic                     v3_probs_valid,
    input  logic              [15:0] v3_probs_q0_16 [NUM_CLASSES],

    output logic                     v2_start,
    input  logic                     v2_done,
    output logic                     v2_img_px_valid,
    output logic signed [ACT_W-1:0]  v2_img_px_in [NUM_PE],
    input  logic                     v2_probs_valid,
    input  logic              [15:0] v2_probs_q0_16 [NUM_CLASSES],

    output logic                     route_start,
    input  logic                     route_done,
    input  logic                     route_to_m2,
    input  logic signed [15:0]       route_entropy_q8_8,
    input  logic              [15:0] route_confidence_q0_16,
    input  logic              [15:0] route_threshold_q0_16
);
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] ADDR_CTRL    = 6'h00;
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] ADDR_TEMP    = 6'h04;
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] ADDR_STATUS  = 6'h08;
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] ADDR_PREDCLS = 6'h0C;
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] ADDR_ENTROPY = 6'h10;
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] ADDR_CONF    = 6'h14;
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] ADDR_THRESH  = 6'h18;
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] ADDR_CYCLES  = 6'h1C;

    logic axi_awready, axi_wready, axi_bvalid;
    logic [C_S_AXI_ADDR_WIDTH-1:0] axi_awaddr;
    assign S_AXI_AWREADY = axi_awready;
    assign S_AXI_WREADY  = axi_wready;
    assign S_AXI_BRESP   = 2'b00;
    assign S_AXI_BVALID  = axi_bvalid;

    logic write_en;
    assign write_en = axi_wready && S_AXI_WVALID && axi_awready && S_AXI_AWVALID;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            axi_awready <= 1'b0; axi_wready <= 1'b0; axi_bvalid <= 1'b0; axi_awaddr <= '0;
        end else begin
            if (!axi_awready && S_AXI_AWVALID && S_AXI_WVALID) begin
                axi_awready <= 1'b1; axi_wready <= 1'b1; axi_awaddr <= S_AXI_AWADDR;
            end else begin
                axi_awready <= 1'b0; axi_wready <= 1'b0;
            end
            if (axi_awready && S_AXI_AWVALID && S_AXI_WVALID && !axi_bvalid) axi_bvalid <= 1'b1;
            else if (S_AXI_BREADY && axi_bvalid) axi_bvalid <= 1'b0;
        end
    end

    logic signed [15:0] reg_temp_q8_8;
    logic                start_pulse;
    logic                status_done, status_model_sel;
    logic [2:0]           reg_predicted_class;
    logic [31:0]          reg_cycles;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reg_temp_q8_8 <= '0;
            start_pulse   <= 1'b0;
        end else begin
            start_pulse <= 1'b0;
            if (write_en) begin
                unique case (axi_awaddr)
                    ADDR_TEMP: reg_temp_q8_8 <= $signed(S_AXI_WDATA[15:0]);
                    ADDR_CTRL: if (S_AXI_WDATA[0]) start_pulse <= 1'b1;
                    default: ;
                endcase
            end
        end
    end

    logic axi_arready, axi_rvalid;
    logic [C_S_AXI_ADDR_WIDTH-1:0] axi_araddr;
    logic [C_S_AXI_DATA_WIDTH-1:0] axi_rdata;
    assign S_AXI_ARREADY = axi_arready;
    assign S_AXI_RVALID  = axi_rvalid;
    assign S_AXI_RRESP   = 2'b00;
    assign S_AXI_RDATA   = axi_rdata;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            axi_arready <= 1'b0; axi_araddr <= '0; axi_rvalid <= 1'b0;
        end else begin
            if (!axi_arready && S_AXI_ARVALID) begin
                axi_arready <= 1'b1; axi_araddr <= S_AXI_ARADDR;
            end else axi_arready <= 1'b0;
            if (axi_arready && S_AXI_ARVALID && !axi_rvalid) axi_rvalid <= 1'b1;
            else if (axi_rvalid && S_AXI_RREADY) axi_rvalid <= 1'b0;
        end
    end

    always_comb begin
        unique case (axi_araddr)
            ADDR_STATUS:  axi_rdata = {30'b0, status_model_sel, status_done};
            ADDR_PREDCLS: axi_rdata = {29'b0, reg_predicted_class};
            ADDR_ENTROPY: axi_rdata = {{16{route_entropy_q8_8[15]}}, route_entropy_q8_8};
            ADDR_CONF:    axi_rdata = {16'b0, route_confidence_q0_16};
            ADDR_THRESH:  axi_rdata = {16'b0, route_threshold_q0_16};
            ADDR_CYCLES:  axi_rdata = reg_cycles;
            default:      axi_rdata = 32'hDEADBEEF;
        endcase
    end

    (* ram_style = "block" *) logic [7:0] img_capture [IMG_HW*IMG_HW];
    logic [$clog2(IMG_HW*IMG_HW)-1:0] img_wr_ptr;

    assign s_axis_img_tready = 1'b1;
    always_ff @(posedge clk) begin
        if (s_axis_img_tvalid && s_axis_img_tready) begin
            img_capture[img_wr_ptr] <= s_axis_img_tdata;
            img_wr_ptr <= s_axis_img_tlast ? '0 : img_wr_ptr + 1'b1;
        end
    end

    typedef enum logic [3:0] {
        S_IDLE, S_STREAM_V3, S_WAIT_V3, S_ROUTE_START, S_WAIT_ROUTE,
        S_STREAM_V2, S_WAIT_V2, S_FINISH
    } state_t;
    state_t state;

    logic [$clog2(IMG_HW*IMG_HW)-1:0] stream_ptr;
    logic [7:0] argmax_idx;

    always_comb begin
        logic [15:0] best;
        logic [2:0]  best_idx;
        logic [15:0] src [NUM_CLASSES];
        src = status_model_sel ? v2_probs_q0_16 : v3_probs_q0_16;
        best = src[0]; best_idx = 3'd0;
        for (int i = 1; i < NUM_CLASSES; i++)
            if (src[i] > best) begin best = src[i]; best_idx = i[2:0]; end
        argmax_idx = {5'b0, best_idx};
    end

    assign route_start = (state == S_ROUTE_START);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            status_done <= 1'b0; status_model_sel <= 1'b0;
            v3_start <= 1'b0; v2_start <= 1'b0;
            v3_img_px_valid <= 1'b0; v2_img_px_valid <= 1'b0;
            stream_ptr <= '0; reg_cycles <= '0;
        end else begin
            v3_start <= 1'b0; v2_start <= 1'b0;
            v3_img_px_valid <= 1'b0; v2_img_px_valid <= 1'b0;

            unique case (state)
                S_IDLE: begin
                    status_done <= 1'b0;
                    reg_cycles  <= '0;
                    if (start_pulse) begin
                        stream_ptr <= '0;
                        v3_start   <= 1'b1;
                        state      <= S_STREAM_V3;
                    end
                end

                S_STREAM_V3: begin
                    reg_cycles <= reg_cycles + 1'b1;
                    v3_img_px_valid <= 1'b1;
                    for (int c = 0; c < NUM_PE; c++)
                        v3_img_px_in[c] <= $signed({1'b0, img_capture[stream_ptr]} - 9'sd128);
                    if (stream_ptr == IMG_HW*IMG_HW-1) begin
                        stream_ptr <= '0;
                        state <= S_WAIT_V3;
                    end else begin
                        stream_ptr <= stream_ptr + 1'b1;
                    end
                end

                S_WAIT_V3: begin
                    reg_cycles <= reg_cycles + 1'b1;
                    if (v3_done && v3_probs_valid)
                        state <= S_ROUTE_START;
                end

                S_ROUTE_START: begin
                    reg_cycles <= reg_cycles + 1'b1;
                    state <= S_WAIT_ROUTE;
                end

                S_WAIT_ROUTE: begin
                    reg_cycles <= reg_cycles + 1'b1;
                    if (route_done) begin
                        if (route_to_m2) begin
                            status_model_sel <= 1'b1;
                            v2_start <= 1'b1;
                            state <= S_STREAM_V2;
                        end else begin
                            status_model_sel <= 1'b0;
                            reg_predicted_class <= argmax_idx[2:0];
                            state <= S_FINISH;
                        end
                    end
                end

                S_STREAM_V2: begin
                    reg_cycles <= reg_cycles + 1'b1;
                    v2_img_px_valid <= 1'b1;
                    for (int c = 0; c < NUM_PE; c++)
                        v2_img_px_in[c] <= $signed({1'b0, img_capture[stream_ptr]} - 9'sd128);
                    if (stream_ptr == IMG_HW*IMG_HW-1) begin
                        stream_ptr <= '0;
                        state <= S_WAIT_V2;
                    end else begin
                        stream_ptr <= stream_ptr + 1'b1;
                    end
                end

                S_WAIT_V2: begin
                    reg_cycles <= reg_cycles + 1'b1;
                    if (v2_done && v2_probs_valid) begin
                        reg_predicted_class <= argmax_idx[2:0];
                        state <= S_FINISH;
                    end
                end

                S_FINISH: begin
                    status_done <= 1'b1;
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
