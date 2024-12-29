`define I_EXP 8
`define I_MAT 7
`define LUT_ADDR 4
`define LUT_DEPTH 2 ** `LUT_ADDR
`define LUT_DATA `I_EXP + `I_MAT + 1

module consmax #(
    parameter   IDATA_BIT = 8,  // Input Data in INT
    parameter   ODATA_BIT = 8,  // Output Data in INT
    parameter   CDATA_BIT = 8,  // Global Config Data

    parameter   EXP_BIT = 8,    // Exponent
    parameter   MAT_BIT = 7,    // Mantissa
    parameter   LUT_DATA  = EXP_BIT + MAT_BIT + 1,  // LUT Data Width (in FP)
    parameter   LUT_ADDR  = IDATA_BIT >> 1,         // LUT Address Width
    parameter   LUT_DEPTH = 2 ** LUT_ADDR           // LUT Depth for INT2FP
)(
    // Global Signals
    input                       clk,
    input                       rstn,

    // Control Signals
    input       [CDATA_BIT-1:0] cfg_consmax_shift,

    // LUT Interface
    input       [LUT_ADDR:0]    lut_waddr,          // bitwidth + 1 for two LUTs
    input                       lut_wen,
    input       [LUT_DATA-1:0]  lut_wdata,

    // Data Signals
    input       [LUT_DATA-1:0] idata,
    input                       idata_valid,
    output  reg [ODATA_BIT-1:0] odata,
    output  reg                 odata_valid
);

    // Clock Gating for Input
    reg     [LUT_DATA-1:0]  idata_reg;
    reg                     idata_valid_reg;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            idata_reg <= 'd0;
            idata_int_reg <= 'd0;
        end
        else if (idata_valid) begin
            idata_reg <= idata;
            idata_int_reg <= idata_int_comb;
        end
    end

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            idata_valid_reg <= 1'b0;
        end
        else begin
            idata_valid_reg <= idata_valid;
        end
    end

    fp2int  #(.EXP_BIT(EXP_BIT), .MAT_BIT(MAT_BIT), .ODATA_BIT(ODATA_BIT), .CDATA_BIT(CDATA_BIT)) fp2int_inst (
        .cfg_consmax_shift      (cfg_consmax_shift),
        .idata                  (idata_reg),
        .odata                  (idata_int_comb)
    );

    // LUT Initialization: Convert INT to FP
    wire    [LUT_ADDR-1:0]  lut_addr    [0:1];
    wire    [LUT_DATA-1:0]  lut_rdata   [0:1];
    wire                    lut_ren;
    reg                     lut_rvalid;

    assign  lut_addr[0] = lut_wen && ~lut_waddr[LUT_ADDR] ? lut_waddr[LUT_ADDR-1:0] :
                                                            idata_int_reg[LUT_ADDR-1:0];
    assign  lut_addr[1] = lut_wen &&  lut_waddr[LUT_ADDR] ? lut_waddr[LUT_ADDR-1:0] :
                                                            idata_int_reg[LUT_ADDR+:LUT_ADDR];
    assign  lut_ren     = lut_wen ? 1'b0 : idata_valid_reg;

    genvar i;
    generate
        for (i = 0; i < 2; i = i + 1) begin: gen_conmax_lut
            mem_sp  lut_inst (
                .clk                (clk),
                .addr               (lut_addr[i]),
                .wen                (lut_wen),
                .wdata              (lut_wdata),
                .ren                (lut_ren),
                .rdata              (lut_rdata[i])
            );
        end
    endgenerate

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            lut_rvalid <= 1'b0;
        end
        else begin
            lut_rvalid <= lut_ren;
        end
    end

    // FP Multiplication: Produce exp(Si)
    wire    [LUT_DATA-1:0]  lut_product;

    // use fpmult for fixed data format
    fmul fpmul_inst (
        .result(lut_product),
        .a_in(lut_rdata[0]),
        .b_in(lut_rdata[1])
    );

    // Convert FP to INT
    wire    [ODATA_BIT-1:0] odata_comb;

    // Output
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            odata <= 'd0;
        end
        else if (lut_rvalid) begin
            odata <= lut_product;
        end
    end

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            odata_valid <= 1'b0;
        end
        else begin
            odata_valid <= lut_rvalid;
        end
    end

endmodule

// =============================================================================
// Floating-Point to Integer Converter

module fp2int #(
    parameter   EXP_BIT = 8,
    parameter   MAT_BIT = 7,

    parameter   IDATA_BIT = EXP_BIT + MAT_BIT + 1,  // FP-Input
    parameter   ODATA_BIT = 8,  // INT-Output
    parameter   CDATA_BIT = 8   // Config
)(
    // Control Signals
    input   [CDATA_BIT-1:0] cfg_consmax_shift,

    // Data Signals
    input   [IDATA_BIT-1:0] idata,
    output  [ODATA_BIT-1:0] odata
);

    localparam  EXP_BASE = 2 ** (EXP_BIT - 1) - 1;

    // Extract Sign, Exponent and Mantissa Field
    reg                     idata_sig;
    reg     [EXP_BIT-1:0]   idata_exp;
    reg     [MAT_BIT:0]     idata_mat;

    always @(*) begin
        idata_sig = idata[IDATA_BIT-1];
        idata_exp = idata[MAT_BIT+:EXP_BIT];
        idata_mat = {1'b1, idata[MAT_BIT-1:0]};
    end

    // Shift and Round Mantissa to Integer
    reg     [MAT_BIT:0]     mat_shift;
    reg     [MAT_BIT:0]     mat_round;

    always @(*) begin
        if (idata_exp >= EXP_BASE) begin    // >= 1.0
            if (MAT_BIT <= (cfg_consmax_shift + (idata_exp - EXP_BASE))) begin // Overflow
                mat_shift = {(MAT_BIT){1'b1}};
                mat_round = mat_shift;
            end
            else begin
                mat_shift = idata_mat >> (MAT_BIT - cfg_consmax_shift - (idata_exp - EXP_BASE));
                mat_round = mat_shift[MAT_BIT:1] + mat_shift[0];
            end
        end
        else begin  // <= 1.0
            if (cfg_consmax_shift < (EXP_BASE - idata_exp)) begin // Underflow
                mat_shift = {(MAT_BIT){1'b0}};
                mat_round = mat_shift;
            end
            else begin
                mat_shift = idata_mat >> (MAT_BIT - cfg_consmax_shift + (EXP_BASE - idata_exp));
                mat_round = mat_shift[MAT_BIT:1] + mat_shift[0];
            end
        end
    end

    // Convert to 2's Complementary Integer
    assign  odata = {idata_sig, idata_sig ? (~mat_round[MAT_BIT-:ODATA_BIT] + 1'b1) : 
                                              mat_round[MAT_BIT-:ODATA_BIT]};

endmodule

module mem_sp 
(
    // Global Signals
    input                       clk,

    // Data Signals
    input       [`LUT_ADDR-1:0]  addr,
    input                       wen,
    input       [`LUT_DATA-1:0]  wdata,
    input                       ren,
    output  reg [`LUT_DATA-1:0]  rdata
);

    // 1. RAM/Memory initialization
    reg [`LUT_DATA-1:0]  mem [0:`LUT_DEPTH-1];

    // 2. Write channel
    always @(posedge clk) begin
        if (wen) begin
            mem[addr] <= wdata;
        end
    end

    // 3. Read channel
    always @(posedge clk) begin
        if (ren) begin
            rdata <= mem[addr];
        end
    end

endmodule

`define BIT_W 16
`define M_W 7
`define EXP_W 8

module fmul(
      input [`BIT_W-1:0] a_in,
      input [`BIT_W-1:0] b_in,
      output [`BIT_W-1:0] result
    );
    
    reg [`M_W+`M_W:0] mul_fix_out;
    
    // Multiply mantissas with implied leading 1
    always @(*) begin
        mul_fix_out = {1'b1, a_in[`M_W-1:0]} * {1'b1, b_in[`M_W-1:0]};
    end
    
    // Zero check
    reg zero_check;
    always @(*) begin
        if ((a_in[`BIT_W-2:`M_W] == 0) || (b_in[`BIT_W-2:`M_W] == 0)) begin
            zero_check = 1'b1;
        end else begin
            zero_check = 1'b0;
        end
    end
    
    // Generate mantissa for the result
    reg [`M_W-1:0] M_result;
    always @(*) begin
        case (mul_fix_out[`M_W+`M_W:`M_W+`M_W-1])
            2'b01: M_result = mul_fix_out[`M_W+`M_W-2:`M_W];
            2'b10, 2'b11: M_result = mul_fix_out[`M_W+`M_W-1:`M_W+1];
            default: M_result = mul_fix_out[`M_W+`M_W-1:`M_W+1];
        endcase
    end
    
    // Overflow check
    reg [`EXP_W:0] e_result0;
    reg [`EXP_W-1:0] e_result;
    reg overflow;
    
    always @(*) begin
        overflow = (zero_check ||
                    ({1'b0, a_in[`BIT_W-2:`M_W]} + {1'b0, b_in[`BIT_W-2:`M_W]} + mul_fix_out[`M_W+`M_W]) < (2'b00 << (`EXP_W - 1)) ||
                    ({1'b0, a_in[`BIT_W-2:`M_W]} + {1'b0, b_in[`BIT_W-2:`M_W]} + mul_fix_out[`M_W+`M_W]) > `EXP_W'hFF);
        
        if (~zero_check) begin
            if (overflow) begin
                e_result0 = {(`EXP_W+1){1'b1}};
            end else begin
                e_result0 = ({1'b0, a_in[`BIT_W-2:`M_W]} + {1'b0, b_in[`BIT_W-2:`M_W]} + mul_fix_out[`M_W+`M_W]) - (2'b00 << (`EXP_W - 1));
            end
        end else begin
            e_result0 = 0;
        end
        e_result = e_result0[`EXP_W-1:0];
    end
    
    // Sign calculation
    wire sign;
    assign sign = a_in[`BIT_W-1] ^ b_in[`BIT_W-1];
    
    // Overflow mask
    wire [`M_W-1:0] overflow_mask;
    assign overflow_mask = overflow ? 0 : {(`M_W){1'b1}};
    
    // Final result assignment
    assign result = {sign, e_result, overflow_mask & M_result};

endmodule

