package sentinel_pkg;

    localparam int CLOCK_FREQ_HZ = 250_000_000;

    localparam int NUM_PE          = 32;
    localparam int MAX_KSIZE       = 5;
    localparam int ACT_W           = 8;
    localparam int WGT_W           = 8;
    localparam int ACC_W           = 32;
    localparam int NUM_CLASSES     = 8;

    typedef enum logic [2:0] {
        LT_POINTWISE   = 3'd0,
        LT_DEPTHWISE   = 3'd1,
        LT_SE          = 3'd2,
        LT_STANDARD3x3 = 3'd3,
        LT_AVGPOOL     = 3'd4,
        LT_FC          = 3'd5
    } layer_type_e;

    typedef enum logic [1:0] {
        ACT_NONE     = 2'd0,
        ACT_RELU6    = 2'd1,
        ACT_HSWISH   = 2'd2,
        ACT_HSIGMOID = 2'd3
    } activation_e;

    typedef struct packed {
        layer_type_e  ltype;
        activation_e  act;
        logic [10:0]  in_h;
        logic [10:0]  in_w;
        logic [9:0]   in_ch;
        logic [9:0]   out_ch;
        logic [2:0]   kernel;
        logic [1:0]   stride;
        logic         use_residual;
        logic [23:0]  weight_offset;
        logic [15:0]  requant_mult;
        logic [4:0]   requant_shift;
    } layer_desc_t;

    localparam logic signed [15:0] TAU_BASE_Q0_16  = 16'd53738;
    localparam logic signed [15:0] TAU_MIN_Q0_16   = 16'd40632;
    localparam logic        [15:0] ALPHA_Q0_16     = 16'd524;
    localparam logic signed [15:0] TCRIT_Q8_8      = 16'sd19200;
endpackage
