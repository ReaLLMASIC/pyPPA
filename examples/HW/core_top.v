`define GBUS_DATA = 64
`define GBUS_ADDR = 12
`define LBUF_DEPTH = 64
`define LBUF_DATA =  64
`define LBUF_ADDR   = $clog2(64)
`define CDATA_BIT = 8
`define ODATA_BIT = 16
`define IDATA_BIT = 8
`define MAC_NUM   = 8
`define WMEM_DEPTH  = 512
`define CACHE_DEPTH = 256

module core_top (
    // Global Signals
    input                       clk,
    input                       rstn,

    // Global Config Signals
    input       [`CDATA_BIT-1:0] cfg_acc_num,
    input       [`ODATA_BIT-1:0] cfg_quant_scale,
    input       [`ODATA_BIT-1:0] cfg_quant_bias,
    input       [`ODATA_BIT-1:0] cfg_quant_shift,

    // Channel - Global Bus to Access Core Memory and MAC Result -> input and output nodes
    // 1. Write Channel
    //      1.1 Chip Interface -> WMEM for Weight Upload
    //      1.2 Chip Interface -> KV Cache for KV Upload (Just Run Attention Test)
    //      1.3 Vector Engine  -> KV Cache for KV Upload (Run Projection and/or Attention)
    // 2. Read Channel
    //      2.1 WMEM       -> Chip Interface for Weight Check
    //      2.2 KV Cache   -> Chip Interface for KV Checnk
    //      2.3 MAC Result -> Vector Engine  for Post Processing
    input       [`GBUS_ADDR-1:0] gbus_addr,
    input                       gbus_wen,
    input       [`GBUS_DATA-1:0] gbus_wdata,
    input                       gbus_ren,
    output  reg [`GBUS_DATA-1:0] gbus_rdata,     // To Chip Interface (Debugging) and Vector Engine (MAC)
    output  reg                 gbus_rvalid,

    // Channel - Core-to-Core Link
    // Vertical for Weight and Key/Value Propagation
    input                       vlink_enable,
    input       [`GBUS_DATA-1:0] vlink_wdata,
    input                       vlink_wen,
    output      [`GBUS_DATA-1:0] vlink_rdata,
    output                      vlink_rvalid,
    // Horizontal for Activation Propagation
    // input                    vlink_enable,   // No HLING_ENABLE for Activaton
    input       [`GBUS_DATA-1:0] hlink_wdata,
    input                       hlink_wen,
    output      [`GBUS_DATA-1:0] hlink_rdata,
    output                      hlink_rvalid,

    // Channel - MAC Operation
    // Core Memory Access for Weight and KV Cache
    input       [`GBUS_ADDR-1:0] cmem_waddr,     // Write Value to KV Cache
    input                       cmem_wen,
    input       [`GBUS_ADDR-1:0] cmem_raddr,
    input                       cmem_ren,
    // Local Buffer Access for Weight and KV Cache
    //input                     lbuf_mux,       // Annotate for Double-Buffering LBUF
    //input       [LBUF_ADDR-1:0] lbuf_waddr,
    //input       [LBUF_ADDR-1:0] lbuf_raddr,
    input                       lbuf_ren,
    input                       lbuf_reuse_ren, //reuse pointer logic, when enable
    input                       lbuf_reuse_rst,  //reuse reset logic, when first round of reset is finished, reset reuse pointer to current normal read pointer value
    output                      lbuf_empty,
    output                      lbuf_reuse_empty,
    output                      lbuf_full,
    output                      lbuf_almost_full,
    // Local Buffer Access for Activation
    //input                     abuf_mux,
    //input       [LBUF_ADDR-1:0] abuf_waddr,
    //input       [LBUF_ADDR-1:0] abuf_raddr,
    input                       abuf_ren,
    input                       abuf_reuse_ren, //reuse pointer logic, when enable
    input                       abuf_reuse_rst,  //reuse reset logic, when first round of reset is finished, reset reuse pointer to current normal read pointer value
    output                      abuf_empty,
    output                      abuf_reuse_empty,
    output                      abuf_full,
    output                      abuf_almost_full
    // MAC Output for Post-Processing in Vector Engine
    // Merged to GBUS
);
    reg       [`CDATA_BIT-1:0] cfg_acc_num_reg;
    reg       [`ODATA_BIT-1:0] cfg_quant_scale_reg;
    reg       [`ODATA_BIT-1:0] cfg_quant_bias_reg;
    reg       [`ODATA_BIT-1:0] cfg_quant_shift_reg;
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            cfg_acc_num_reg <= 'd0;
            cfg_quant_scale_reg <= 'd0;
            cfg_quant_bias_reg <= 'd0;
            cfg_quant_shift_reg <= 'd0;
        end
        else begin
            cfg_acc_num_reg <= cfg_acc_num;
            cfg_quant_scale_reg <= cfg_quant_scale;
            cfg_quant_bias_reg <= cfg_quant_bias;
            cfg_quant_shift_reg <= cfg_quant_shift;
        end
    end
    // =============================================================================
    // Core Memory Module for Weight and KV Cache Access

    wire    [`GBUS_DATA-1:0]     gbus_mem_rdata;
    wire                        gbus_mem_rvalid;

    wire    [`GBUS_DATA-1:0]     cmem_wdata;
    wire                        cmem_wen_comb;

    wire    [`LBUF_DATA-1:0]     lbuf_rdata;
    wire                        lbuf_rvalid;

    core_mem mem_inst (
        .clk                    (clk),
        .rstn                    (rstn),

        .gbus_addr              (gbus_addr),
        .gbus_wen               (gbus_wen),
        .gbus_wdata             (gbus_wdata),
        .gbus_ren               (gbus_ren),
        .gbus_rdata             (gbus_mem_rdata),
        .gbus_rvalid            (gbus_mem_rvalid),

        .clink_enable           (vlink_enable),
        .clink_wdata            (vlink_wdata),
        .clink_wen              (vlink_wen),
        .clink_rdata            (vlink_rdata),
        .clink_rvalid           (vlink_rvalid),

        .cmem_waddr             (cmem_waddr),
        .cmem_wen               (cmem_wen_comb),
        .cmem_wdata             (cmem_wdata),
        .cmem_raddr             (cmem_raddr),
        .cmem_ren               (cmem_ren),

        //.lbuf_mux             (lbuf_mux),
        //.lbuf_waddr             (lbuf_waddr),
        //.lbuf_raddr             (lbuf_raddr),
        .lbuf_ren               (lbuf_ren),
        .lbuf_reuse_ren         (lbuf_reuse_ren),
        .lbuf_reuse_rst         (lbuf_reuse_rst),
        .lbuf_rdata             (lbuf_rdata),
        .lbuf_empty             (lbuf_empty),
        .lbuf_reuse_empty       (lbuf_reuse_empty),
        .lbuf_rvalid            (lbuf_rvalid),
        .lbuf_full              (lbuf_full),
        .lbuf_almost_full       (lbuf_almost_full)
    );

    // =============================================================================
    // Core Buffer Module for Activation Access

    wire    [`LBUF_DATA-1:0]     abuf_rdata;
    wire                        abuf_rvalid;

    core_buf buf_inst (
        .clk                    (clk),
        .rstn                    (rstn),

        .clink_wdata            (hlink_wdata),
        .clink_wen              (hlink_wen),
        .clink_rdata            (hlink_rdata),
        .clink_rvalid           (hlink_rvalid),

        //.abuf_mux             (abuf_mux),
        //.abuf_waddr             (abuf_waddr),
        //.abuf_raddr             (abuf_raddr),
        .abuf_ren               (abuf_ren),
        .abuf_rdata             (abuf_rdata),
        .abuf_reuse_ren         (abuf_reuse_ren),
        .abuf_reuse_rst         (abuf_reuse_rst),
        .abuf_empty             (abuf_empty),
        .abuf_reuse_empty       (abuf_reuse_empty),
        .abuf_full              (abuf_full),
        .abuf_almost_full       (abuf_almost_full),
        .abuf_rvalid            (abuf_rvalid)
    );

    // =============================================================================
    // MAC Module

    wire    [(`IDATA_BIT*2+$clog2(`MAC_NUM))-1:0]     mac_odata;
    wire                                            mac_odata_valid;

    core_mac mac_inst (
        .clk                    (clk),
        .rstn                    (rstn),

        .idataA                 (abuf_rdata),
        .idataB                 (lbuf_rdata),
        .idata_valid            (abuf_rvalid && lbuf_rvalid),
        .odata                  (mac_odata),
        .odata_valid            (mac_odata_valid)
    );
    //cfg_acc_num delay logic
    parameter REMAIN_STAGE = (($clog2(`MAC_NUM)+1)/2-1);
    logic [REMAIN_STAGE-1:0][`CDATA_BIT-1:0] cfg_acc_num_sync;
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            cfg_acc_num_sync <= '0;
        end else begin
            for(int i=0;i<REMAIN_STAGE;i++) begin
                if(i==0) begin
                    cfg_acc_num_sync[i] <= cfg_acc_num_reg;
                end
                else begin
                    cfg_acc_num_sync[i] <= cfg_acc_num_sync[i-1];
                end
            end
        end
    end
    // =============================================================================
    // ACC Module

    wire    [`ODATA_BIT-1:0]     acc_odata;
    wire                        acc_odata_valid;

    core_acc acc_inst (
        .clk                    (clk),
        .rstn                   (rstn),
        .cfg_acc_num            (cfg_acc_num_sync[REMAIN_STAGE-1]),

        .idata                  (mac_odata),
        .idata_valid            (mac_odata_valid),
        .odata                  (acc_odata),
        .odata_valid            (acc_odata_valid)
    );

    // =============================================================================
    // Quantization Module

    wire    [`IDATA_BIT-1:0]     quant_odata;
    wire                        quant_odata_valid;

    core_quant quant_inst (
        .clk                    (clk),
        .rstn                    (rstn),

        .cfg_quant_scale        (cfg_quant_scale_reg),
        .cfg_quant_bias         (cfg_quant_bias_reg),
        .cfg_quant_shift        (cfg_quant_shift_reg),

        .idata                  (acc_odata),
        .idata_valid            (acc_odata_valid),
        .odata                  (quant_odata),
        .odata_valid            (quant_odata_valid)
    );

    // =============================================================================
    // MAC Output Series to Parallel. To Match GBUS Bitwidth
    // TODO: Support byte mask in case the results can't form a complete word in the last transmission

    wire    [`GBUS_DATA-1:0]     core_odata;
    wire                        core_odata_valid;

    align_s2p mac_s2p (
        .clk                    (clk),
        .rstn                    (rstn),

        .idata                  (quant_odata),
        .idata_valid            (quant_odata_valid),
        .odata                  (core_odata),
        .odata_valid            (core_odata_valid)
    );

    // =============================================================================
    // Core Output Management

    // 1. Core -> KV Cache for Value
    assign  cmem_wdata    = core_odata;
    assign  cmem_wen_comb = core_odata_valid && cmem_wen;

    // 2. Core -> GBUS
    //      2.1 Weight or KV Cache -> GBUS for Debugging
    //      2.2 MAC Result         -> GBUS for Post Processing in Vector Engine
    always @(*) begin
        gbus_rvalid = gbus_mem_rvalid || core_odata_valid;
        if (gbus_mem_rvalid) begin // Read Weight and KV Cache only when GBUS_REN is set to high.
            gbus_rdata = gbus_mem_rdata;
        end
        else begin // Default: Read MAC Result when ODATA_VALID is high.
            gbus_rdata = core_odata;
        end
    end

endmodule 

module align_s2p (
    // Global Signals
    input                       clk,
    input                       rstn, //jdamle change - was rst

    // Data Signals
    input       [`IDATA_BIT-1:0] idata,
    input                       idata_valid,
    output  reg [`GBUS_DATA-1:0] odata,
    output  reg                 odata_valid
);

    localparam  REG_NUM = `GBUS_DATA / `IDATA_BIT;
    localparam  ADDR_BIT = $clog2(REG_NUM+1);

    // 1. Register file / buffer
    reg     [`IDATA_BIT-1:0] regfile [0:REG_NUM-1];
    reg     [ADDR_BIT-1:0]  regfile_addr;           

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            regfile_addr <= 'd0;
        end
        else if (idata_valid) begin
            regfile_addr <= (regfile_addr + 1'b1)%REG_NUM;
        end
    end

    always @(posedge clk) begin
        if (idata_valid) begin
            regfile[regfile_addr] <= idata;
        end
    end

    // 2. Output
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            odata_valid <= 1'b0;
        end
        else begin
            if ((regfile_addr==REG_NUM-1) && idata_valid) begin
                odata_valid <= 1'b1;
            end
            else begin
                odata_valid <= 1'b0;
            end
        end
    end

    genvar i;
    generate
        for (i = 0; i < REG_NUM; i = i + 1) begin:gen_pal
            always @(*) begin
                odata[i*`IDATA_BIT+:`IDATA_BIT] = regfile[i];
            end
        end
    endgenerate
    
endmodule
