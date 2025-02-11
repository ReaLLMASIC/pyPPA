`define VNUM = $(n_cols)
`define HNUM = $(n_heads)
`define N_EMBED = $(n_embed)
`define GBUS_DATA = $(gbus_width) 
`define GBUS_ADDR = 12
`define MAC_NUM   = `GBUS_DATA/8
`define LBUF_DEPTH = 64
`define LBUF_DATA =  64
`define LBUF_ADDR   = $clog2(64)
`define CDATA_BIT = 8
`define ODATA_BIT = 16
`define IDATA_BIT = 8
`define WMEM_DEPTH  = 512
`define WMEM_ADDR = $clog2(512)
`define CACHE_DEPTH = $(max_context_length)
`define CACHE_ADDR = $clog2(`CACHE_DEPTH)
`define ABUF_DEPTH = 64
`define ABUF_DATA =  64
`define ABUF_ADDR  = $clog2(64)
`define MUL_ODATA_BIT = 16
`define MAC_ODATA_BIT = 16+$clog2(8)
`define ADD_IDATA_BIT = 16
`define ADD_ODATA_BIT = 16 + $clog2(8)
`define ACC_IDATA_BIT = (16+$clog2(8))
`define QUANT_IDATA_BIT = 16
`define QUANT_ODATA_BIT = 8
`define ALERT_DEPTH = 3

///////////////////////////Core Array///////////////////////////
module core_array #(
	parameter HNUM = `HNUM,
    parameter VNUM = `VNUM,

    parameter GBUS_DATA = `GBUS_DATA,
    parameter GBUS_ADDR = 12,

    parameter LBUF_DEPTH = 64,
    parameter LBUF_DATA =  64,
    parameter LBUF_ADDR   = $clog2(LBUF_DEPTH),

    parameter CDATA_BIT = 8,

    parameter ODATA_BIT = 16,
    parameter IDATA_BIT = 8,
    parameter MAC_NUM   = `MAC_NUM,

    parameter   WMEM_DEPTH  = 512,
    parameter   CACHE_DEPTH = `CACHE_DEPTH 
)(
    // Global Signals
    input                       clk,
    input                       rstn,
  	input     [ODATA_BIT-1:0] cfg_quant_scale,
	input     [ODATA_BIT-1:0] cfg_quant_bias,
	input     [ODATA_BIT-1:0] cfg_quant_shift,
	input     [CDATA_BIT-1:0] cfg_consmax_shift, 
	
	
	input    [HNUM-1:0][CDATA_BIT-1:0]     cfg_acc_num,
	input            [HNUM-1:0][GBUS_ADDR-1:0]     in_GBUS_ADDR,
    input            [HNUM * VNUM - 1:0]                           gbus_wen,
    input            [HNUM-1:0][GBUS_DATA-1:0]     gbus_wdata,   
    input            [HNUM * VNUM - 1:0]                           gbus_ren,
    output   reg   [HNUM-1:0][GBUS_DATA-1:0]     gbus_rdata,     
    output   reg   [HNUM * VNUM - 1:0]        gbus_rvalid,
    // Channel - Core-to-Core Link
    // Vertical for Weight and Key/Value Propagation
    input                                           vlink_enable,
    input            [VNUM-1:0][GBUS_DATA-1:0]     vlink_wdata,
    input            [VNUM-1:0]                    vlink_wen,
    output   reg   [VNUM-1:0][GBUS_DATA-1:0]     vlink_rdata,
    output   reg   [VNUM-1:0]                    vlink_rvalid,
    // Horizontal for Activation Propagation
    input            [HNUM-1:0][GBUS_DATA-1:0]     hlink_wdata,    //hlink_wdata go through reg, to hlink_rdata
    input            [HNUM-1:0]                    hlink_wen,     
    output   reg   [HNUM-1:0][GBUS_DATA-1:0]     hlink_rdata,
    output   reg   [HNUM-1:0]                    hlink_rvalid,
    // Channel - MAC Operation
    // Core Memory Access for Weight and KV Cache
    //input            CMEM_ARR_PACKET                arr_cmem,
	input 	[HNUM-1:0][VNUM-1:0][GBUS_ADDR-1:0]  cmem_waddr,      // Write Value to KV Cache, G_BUS -> KV Cache, debug.
    input 	[HNUM-1:0][VNUM-1:0]    cmem_wen,
    input	[HNUM-1:0][VNUM-1:0][GBUS_ADDR-1:0]  cmem_raddr,
    input	[HNUM-1:0][VNUM-1:0]    cmem_ren,
	
    // Local Buffer Access for Weight and KV Cache
    output           [HNUM-1:0][VNUM-1:0]        lbuf_empty,
    output           [HNUM-1:0][VNUM-1:0]        lbuf_reuse_empty,
    input            [HNUM-1:0][VNUM-1:0]        lbuf_reuse_ren, //reuse pointer logic, when enable
    input            [HNUM-1:0][VNUM-1:0]        lbuf_reuse_rst,  //reuse reset logic, when first round of reset is finished, reset reuse pointer to current normal read pointer value
    output           [HNUM-1:0][VNUM-1:0]        lbuf_full,
    output           [HNUM-1:0][VNUM-1:0]        lbuf_almost_full,
    input            [HNUM-1:0][VNUM-1:0]        lbuf_ren,
    // Local Buffer access for Activation
    output           [HNUM-1:0][VNUM-1:0]        abuf_empty,
    output           [HNUM-1:0][VNUM-1:0]        abuf_reuse_empty,
    input            [HNUM-1:0][VNUM-1:0]        abuf_reuse_ren, //reuse pointer logic, when enable
    input            [HNUM-1:0][VNUM-1:0]        abuf_reuse_rst,  //reuse reset logic, when first round of reset is finished, reset reuse pointer to current normal read pointer value
    output           [HNUM-1:0][VNUM-1:0]        abuf_full,
    output           [HNUM-1:0][VNUM-1:0]        abuf_almost_full,
    input            [HNUM-1:0][VNUM-1:0]        abuf_ren
);

    //from spi
    //CFG_ARR_PACKET arr_cfg_reg;
    reg       [ODATA_BIT-1:0] reg_cfg_quant_scale;
    reg       [ODATA_BIT-1:0] reg_cfg_quant_bias;
    reg       [ODATA_BIT-1:0] reg_cfg_quant_shift;
    reg       [CDATA_BIT-1:0] reg_cfg_consmax_shift;

    always @(posedge clk or negedge rstn) begin
    if(!rstn) begin
        reg_cfg_quant_scale<={ODATA_BIT{1'b0}};
        reg_cfg_quant_bias<={ODATA_BIT{1'b0}};
        reg_cfg_quant_shift<={ODATA_BIT{1'b0}};
        reg_cfg_consmax_shift<={ODATA_BIT{1'b0}};
    end
    else begin
        reg_cfg_quant_scale<=cfg_quant_scale;
        reg_cfg_quant_bias<=cfg_quant_bias;
        reg_cfg_quant_shift<=cfg_quant_shift;
        reg_cfg_consmax_shift<=cfg_consmax_shift;
    end
    end

    reg [CDATA_BIT-1:0] array_cfg_acc_num_reg_flat [0:(HNUM*VNUM)-1];
    integer k;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            for (k = 0; k < HNUM * VNUM; k = k + 1) begin
                array_cfg_acc_num_reg_flat[k] <= 0;
            end
        end else begin
            for (k = 0; k < HNUM * VNUM; k = k + 1) begin
                if (k % VNUM == 0) begin
                    array_cfg_acc_num_reg_flat[k] <= cfg_acc_num[k / VNUM];
                end else begin
                    array_cfg_acc_num_reg_flat[k] <= array_cfg_acc_num_reg_flat[k - 1];
                end
            end
        end
    end

    reg [GBUS_DATA-1:0] vlink_wdata_temp [0:(HNUM * VNUM) - 1];
    reg [GBUS_DATA-1:0] vlink_rdata_temp [0:(HNUM * VNUM) - 1];
    reg vlink_wen_temp [0:(HNUM * VNUM) - 1];
    reg vlink_rvalid_temp [0:(HNUM * VNUM) - 1];

    reg [GBUS_DATA-1:0] hlink_wdata_temp [0:(HNUM * VNUM) - 1];
    reg [GBUS_DATA-1:0] hlink_rdata_temp [0:(HNUM * VNUM) - 1];
    reg hlink_wen_temp [0:(HNUM * VNUM) - 1];
    reg hlink_rvalid_temp [0:(HNUM * VNUM) - 1];

    always @(*) begin
        integer i, j;

        // Compute
        for (i = 0; i < HNUM; i = i + 1) begin
            for (j = 0; j < VNUM; j = j + 1) begin
                // vlink connections
                if (i == 0) begin
                    vlink_wdata_temp[i * VNUM + j] = vlink_wdata[j];
                    vlink_wen_temp[i * VNUM + j] = vlink_wen[j];
                end else begin
                    vlink_wdata_temp[i * VNUM + j] = vlink_rdata_temp[(i-1) * VNUM + j];
                    vlink_wen_temp[i * VNUM + j] = vlink_rvalid_temp[(i-1) * VNUM + j];
                end

                // hlink connections
                if (j == 0) begin
                    hlink_wdata_temp[i * VNUM + j] = hlink_wdata[i];
                    hlink_wen_temp[i * VNUM + j] = hlink_wen[i];
                end else begin
                    hlink_wdata_temp[i * VNUM + j] = hlink_rdata_temp[i * VNUM + (j-1)];
                    hlink_wen_temp[i * VNUM + j] = hlink_rvalid_temp[i * VNUM + (j-1)];
                end

                // Update outputs for boundary conditions
                if (i == HNUM - 1) begin
                    vlink_rdata[j] = vlink_rdata_temp[i * VNUM + j];
                    vlink_rvalid[j] = vlink_rvalid_temp[i * VNUM + j];
                end else begin
                    vlink_rvalid[j] = 1'b0;
                    vlink_rdata[j] = 1'b0;
                end

                if (j == VNUM - 1) begin
                    hlink_rdata[i] = hlink_rdata_temp[i * VNUM + j];
                    hlink_rvalid[i] = hlink_rvalid_temp[i * VNUM + j];
                end else begin
                    hlink_rdata[i] = 1'b0;
                end
            end
        end
    end

    reg [GBUS_ADDR-1:0] GBUS_ADDR_temp_flat [0:HNUM-1][0:VNUM-1];
    reg [GBUS_DATA-1:0] gbus_wdata_temp_flat [0:HNUM-1][0:VNUM-1];
    reg [GBUS_DATA-1:0] gbus_rdata_temp_flat [0:HNUM-1][0:VNUM-1];


    always @(*) begin
        integer i, j;

        // Populate gbus arrays based on conditions
        for (i = 0; i < HNUM; i = i + 1) begin
            for (j = 0; j < VNUM; j = j + 1) begin
                // gbus_wdata_temp: Write data logic
                if (gbus_wen[i * VNUM + j]) begin
                    gbus_wdata_temp_flat[i][j] = gbus_wdata[i];
                end

                // GBUS_ADDR_temp: Address logic
                if (gbus_wen[i * VNUM + j] | gbus_ren[i * VNUM + j]) begin
                    GBUS_ADDR_temp_flat[i][j] = in_GBUS_ADDR[i];
                end
            end
        end

        for (i = 0; i < HNUM; i = i + 1) begin
            gbus_rdata[i] = 0; // Initialize to 0
            for (j = 0; j < VNUM; j = j + 1) begin
                if (gbus_rvalid[i * VNUM + j]) begin
                    gbus_rdata[i] = gbus_rdata_temp_flat[i][j];
                end 
            end
        end
    end

      
    generate
      for (genvar i = 0; i < HNUM; i = i+1) begin : gen_row
        for (genvar j = 0; j < VNUM; j = j+1) begin : gen_col
            	core_top core_top_instance (
                        .clk           (clk),
                        .rstn          (rstn),
                        .cfg_acc_num   (array_cfg_acc_num_reg_flat[i*VNUM+j]),
                        .cfg_quant_scale (cfg_quant_scale),
                        .cfg_quant_bias (cfg_quant_bias),
                        .cfg_quant_shift (cfg_quant_shift),
                        .gbus_addr     (GBUS_ADDR_temp_flat[i][j]), //gbus to weight mem, gbus to kv cache
                        .gbus_wen      (gbus_wen[i * VNUM + j]),
                        .gbus_wdata    (gbus_wdata_temp_flat[i][j]),
                        .gbus_ren      (gbus_ren[i * VNUM + j]),
                        .gbus_rdata    (gbus_rdata_temp_flat[i][j]),
                        .gbus_rvalid   (gbus_rvalid[i * VNUM + j]),
                        .vlink_enable  (vlink_enable),
                        .vlink_wdata   (vlink_wdata_temp[i * VNUM + j]), // access lbuf
                        .vlink_wen     (vlink_wen_temp[i * VNUM + j]),
                        .vlink_rdata   (vlink_rdata_temp[i * VNUM + j]),
                        .vlink_rvalid  (vlink_rvalid_temp[i * VNUM + j]),
                        .hlink_wdata   (hlink_wdata_temp[i * VNUM + j]), // access abuf
                        .hlink_wen     (hlink_wen_temp[i * VNUM + j]),
                        .hlink_rdata   (hlink_rdata_temp[i * VNUM + j]),
                        .hlink_rvalid  (hlink_rvalid_temp[i * VNUM + j]),
                        .cmem_waddr    (cmem_waddr[i][j]),
                        .cmem_wen      (cmem_wen[i][j]), //cmem_wen control, when high, mac output will send to cmem, if gbus_ren is not high previous cycle, mac output will send to gbus too.
                        .cmem_raddr    (cmem_raddr[i][j]),
                        .cmem_ren      (cmem_ren[i][j]),
                        .lbuf_full     (lbuf_full[i][j]),
                        .lbuf_almost_full(lbuf_almost_full[i][j]),
                        .lbuf_empty    (lbuf_empty[i][j]),
                        .lbuf_reuse_empty(lbuf_reuse_empty[i][j]),
                        .lbuf_ren      (lbuf_ren[i][j]),
                        .lbuf_reuse_ren(lbuf_reuse_ren[i][j]),
                        .lbuf_reuse_rst(lbuf_reuse_rst[i][j]),
                        .abuf_full     (abuf_full[i][j]),
                        .abuf_almost_full(abuf_almost_full[i][j]),
                        .abuf_empty    (abuf_empty[i][j]),
                        .abuf_reuse_empty(abuf_reuse_empty[i][j]),
                        .abuf_reuse_ren(abuf_reuse_ren[i][j]),
                        .abuf_reuse_rst(abuf_reuse_rst[i][j]),
                        .abuf_ren      (abuf_ren[i][j])
                    );
        	end
    	end
    endgenerate

endmodule

      
///////////////////////////Core Top//////////////////////////
module core_top #(
    parameter   GBUS_DATA   = 64,
    parameter   GBUS_ADDR   = 12,

    parameter   WMEM_DEPTH  = 512,
    parameter   CACHE_DEPTH = 256,

    parameter   LBUF_DATA   = 64,
    parameter   LBUF_DEPTH  = 64,

    parameter   MAC_NUM   = 8,
    parameter   IDATA_BIT = 8,
    parameter   ODATA_BIT = 16,

    parameter   CDATA_BIT = 8,
    parameter LBUF_ADDR = $clog2(64)
)(
  
    input                       clk,
    input                       rstn,

    input       [CDATA_BIT-1:0] cfg_acc_num,
    input       [ODATA_BIT-1:0] cfg_quant_scale,
    input       [ODATA_BIT-1:0] cfg_quant_bias,
    input       [ODATA_BIT-1:0] cfg_quant_shift,

    input       [GBUS_ADDR-1:0] gbus_addr,
    input                       gbus_wen,
    input       [GBUS_DATA-1:0] gbus_wdata,
    input                       gbus_ren,
    output  reg [GBUS_DATA-1:0] gbus_rdata,    
    output  reg                 gbus_rvalid,

    input                       vlink_enable,
    input       [GBUS_DATA-1:0] vlink_wdata,
    input                       vlink_wen,
    output      [GBUS_DATA-1:0] vlink_rdata,
    output                      vlink_rvalid,
  
    input       [GBUS_DATA-1:0] hlink_wdata,
    input                       hlink_wen,
    output      [GBUS_DATA-1:0] hlink_rdata,
    output                      hlink_rvalid,

    input       [GBUS_ADDR-1:0] cmem_waddr,     
    input                       cmem_wen,
    input       [GBUS_ADDR-1:0] cmem_raddr,
    input                       cmem_ren,

    input                       lbuf_ren,
    input                       lbuf_reuse_ren, 
    input                       lbuf_reuse_rst, 
    output                      lbuf_empty,
    output                      lbuf_reuse_empty,
    output                      lbuf_full,
    output                      lbuf_almost_full,

    input                       abuf_ren,
    input                       abuf_reuse_ren, 
    input                       abuf_reuse_rst, 
    output                      abuf_empty,
    output                      abuf_reuse_empty,
    output                      abuf_full,
    output                      abuf_almost_full
);
  
  
    reg       [CDATA_BIT-1:0] cfg_acc_num_reg;
    reg       [ODATA_BIT-1:0] cfg_quant_scale_reg;
    reg       [ODATA_BIT-1:0] cfg_quant_bias_reg;
    reg       [ODATA_BIT-1:0] cfg_quant_shift_reg;
  
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

    wire    [GBUS_DATA-1:0]     gbus_mem_rdata;
    wire                        gbus_mem_rvalid;

    wire    [GBUS_DATA-1:0]     cmem_wdata;
    wire                        cmem_wen_comb;

    wire    [LBUF_DATA-1:0]     lbuf_rdata;
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

    wire    [LBUF_DATA-1:0]     abuf_rdata;
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

    wire    [(IDATA_BIT*2+$clog2(MAC_NUM))-1:0]     mac_odata;
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
    parameter REMAIN_STAGE = (($clog2(MAC_NUM)+1)/2-1);
    logic [REMAIN_STAGE-1:0][CDATA_BIT-1:0] cfg_acc_num_sync;
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            cfg_acc_num_sync <= '0;
        end else begin
          for(integer i=0;i<REMAIN_STAGE;i++) begin
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

    wire    [ODATA_BIT-1:0]     acc_odata;
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

    wire    [IDATA_BIT-1:0]     quant_odata;
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

    wire    [GBUS_DATA-1:0]     core_odata;
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


module align_s2p #(
    parameter IDATA_BIT = 8,
    parameter GBUS_DATA = 64
)(
    // Global Signals
    input                       clk,
    input                       rstn, //jdamle change - was rst

    // Data Signals
    input       [IDATA_BIT-1:0] idata,
    input                       idata_valid,
    output  reg [GBUS_DATA-1:0] odata,
    output  reg                 odata_valid
);

    localparam  REG_NUM = GBUS_DATA / IDATA_BIT;
    localparam  ADDR_BIT = $clog2(REG_NUM+1);

    // 1. Register file / buffer
    reg     [IDATA_BIT-1:0] regfile [0:REG_NUM-1];
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
                odata[i*IDATA_BIT+:IDATA_BIT] = regfile[i];
            end
        end
    endgenerate
endmodule

///////////////////////////Core Mem//////////////////////////
module core_mem #(
    parameter LBUF_DATA = 64,
    parameter GBUS_DATA = 64,
    parameter GBUS_ADDR = 12,
    parameter LBUF_ADDR = 64,
    parameter WMEM_ADDR = $clog2(512),
    parameter CACHE_ADDR = $clog2(256),
    parameter LBUF_DEPTH = 64,
    parameter ALERT_DEPTH = 3
    )(
    // Global Signals
    input                       clk,
    input                       rstn,

    // Channel - Global Bus (GBUS) to Access Core Memory (WMEM and KV Cache)
    // Data Upload from (1) Chip Interface and (2) Vector Engine
    input       [GBUS_ADDR-1:0] gbus_addr,
    input                       gbus_wen,
    input       [GBUS_DATA-1:0] gbus_wdata,
    input                       gbus_ren,
    output  reg [GBUS_DATA-1:0] gbus_rdata,
    output  reg                 gbus_rvalid,

    // Channel - Core-to-Core Link (CLINK)
    // Global Config Signals
    input                       clink_enable,
    // No WADDR. The data from neighboring core is sent to MAC directly.
    input       [GBUS_DATA-1:0] clink_wdata,
    input                       clink_wen,
    // No RADDR. The data to neighboring core is the same as the current operand.
    output  reg [GBUS_DATA-1:0] clink_rdata,
    output  reg                 clink_rvalid,

    // Channel - Core Memory for MAC Operation
    // Write back results from MAC directly.
    input       [GBUS_ADDR-1:0] cmem_waddr,         // Assume WMEM_ADDR >= CACHE_ADDR
    input                       cmem_wen,
    input       [GBUS_DATA-1:0] cmem_wdata,
    // Read data to LBUF. No RDATA, Sent data to LBUF directly in this module.
    input       [GBUS_ADDR-1:0] cmem_raddr,
    input                       cmem_ren,

    // Channel - Local Memory (LBUF) for MAC Operation
    //input                     lbuf_mux,           // Annotate for Double-Buffering LBUF
    //input       [LBUF_ADDR-1:0] lbuf_waddr,         // No WDATA or WEN. Receive data from CMEM directly in this moduel.
    //input       [LBUF_ADDR-1:0] lbuf_raddr,
    input                       lbuf_ren,
    output      [LBUF_DATA-1:0] lbuf_rdata,         // To MAC
    output  reg                 lbuf_rvalid,
    output  reg                 lbuf_empty,
    output  reg                 lbuf_reuse_empty,
    output  reg                 lbuf_full,
    //for activation reuse
    input                       lbuf_reuse_ren, //reuse pointer logic, when enable
    input                       lbuf_reuse_rst,  //reuse reset logic, when first round of reset is finished, reset reuse pointer to current normal read pointer value
    output  reg                 lbuf_almost_full  //reuse reset logic, when first round of reset is finished, reset reuse pointer to current normal read pointer value
);

    // =============================================================================
    // Memory Instantization

    // 1. Single-Port Weight Memory
    reg     [WMEM_ADDR-1:0]     wmem_addr;
    reg                         wmem_wen;
    reg     [GBUS_DATA-1:0]     wmem_wdata;
    reg                         wmem_ren;
    wire    [GBUS_DATA-1:0]     wmem_rdata;
    reg                         wmem_rvalid; //not used for anything

    mem_sp_wmem wmem_inst (
        .clk                    (clk),
        .addr                   (wmem_addr),
        .wen                    (wmem_wen),
        .wdata                  (wmem_wdata),
        .ren                    (wmem_ren),
        .rdata                  (wmem_rdata)
    );

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            wmem_rvalid <= 1'b0;
        end
        else begin
            wmem_rvalid <= wmem_ren;
        end
    end

    // 2. Single-Port KV Cache
    reg     [CACHE_ADDR-1:0]    cache_addr;
    reg                         cache_wen;
    reg     [GBUS_DATA-1:0]     cache_wdata;
    reg                         cache_ren;
    wire    [GBUS_DATA-1:0]     cache_rdata;
    reg                         cache_rvalid;

    mem_sp_cache cache_inst (
        .clk                    (clk),
        .addr                   (cache_addr),
        .wen                    (cache_wen),
        .wdata                  (cache_wdata),
        .ren                    (cache_ren),
        .rdata                  (cache_rdata)
    );

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            cache_rvalid <= 1'b0;
        end
        else begin
            cache_rvalid <= cache_ren;
        end
    end

    // 3. Dual-Port or Double-Buffering LBUF
    // TODO: Design Exploration for DP/DB and SRAM/REGFILE/DFF.
    wire    [LBUF_DATA-1:0]     lbuf_wdata;     // Series_to_Parallel -> LBUF_WDATA
    wire    [LBUF_DATA-1:0]     lbuf_rdata_mem;
    wire                        lbuf_wen;
    reg    [LBUF_ADDR:0]     lbuf_waddr; //was wire before
    reg    [LBUF_ADDR:0]     lbuf_raddr; //was wire before
    reg    [LBUF_ADDR:0]       reuse_raddr; //for reuse pointer.
    reg    [LBUF_ADDR-1:0]     lbuf_raddr_mux;
    assign lbuf_raddr_mux= lbuf_reuse_ren ? reuse_raddr[LBUF_ADDR-1:0] : lbuf_raddr[LBUF_ADDR-1:0];
    mem_dp_lbuf lbuf_inst (
        .clk                    (clk),
        .waddr                  (lbuf_waddr[LBUF_ADDR-1:0]),
        .wen                    (lbuf_wen),
        .wdata                  (lbuf_wdata),
        .raddr                  (lbuf_raddr[LBUF_ADDR-1:0]),
        .ren                    (lbuf_ren),
        .rdata                  (lbuf_rdata_mem) //was lbuf_rdata
    );

    always @(posedge clk or negedge rstn) begin
        if(~rstn)begin
            lbuf_raddr <= '0;
            lbuf_waddr <= '0;
            reuse_raddr <= '0;
        end else begin

            if(lbuf_ren & lbuf_wen) begin
                lbuf_raddr <= lbuf_raddr + 1;
                lbuf_waddr <= lbuf_waddr + 1;
                reuse_raddr<= reuse_raddr+ 1;
            end else if(lbuf_ren & ~lbuf_empty) begin
                lbuf_raddr <= lbuf_raddr + 1;
                reuse_raddr<= reuse_raddr+ 1;
            end else if(lbuf_wen & ~lbuf_full) begin
                lbuf_waddr <= lbuf_waddr + 1;
            end

            if(lbuf_reuse_ren & lbuf_wen & ~lbuf_reuse_rst) begin
                reuse_raddr<= reuse_raddr+ 1;
                lbuf_waddr <= lbuf_waddr + 1;
            end else if(lbuf_reuse_ren & lbuf_wen & lbuf_reuse_rst) begin
                reuse_raddr<= lbuf_raddr;
                lbuf_waddr <= lbuf_waddr + 1;
            end 
            else if(lbuf_reuse_ren & ~lbuf_empty & ~lbuf_reuse_rst) begin
                reuse_raddr<= reuse_raddr+ 1;
            end else if(lbuf_reuse_ren & ~lbuf_empty & lbuf_reuse_rst) begin
                reuse_raddr<= lbuf_raddr;
            end
        end
    end

    assign lbuf_empty = (lbuf_raddr == lbuf_waddr);
    assign lbuf_reuse_empty = (reuse_raddr == lbuf_waddr);
    assign lbuf_full = (lbuf_raddr[LBUF_ADDR] ^ lbuf_waddr[LBUF_ADDR]) & //should abuf_raddr[LBUF_ADDR] be  at [LBUF_ADDR-1] instead?
        (lbuf_raddr[LBUF_ADDR-1:0] == lbuf_waddr[LBUF_ADDR-1:0]);
    assign lbuf_rdata = lbuf_rdata_mem;

    always@(*) begin
        if(lbuf_raddr[LBUF_ADDR] ^ lbuf_waddr[LBUF_ADDR])
            lbuf_almost_full=((lbuf_raddr[LBUF_ADDR-1:0]-lbuf_waddr[LBUF_ADDR-1:0])<=ALERT_DEPTH);
        else
            lbuf_almost_full=((lbuf_waddr[LBUF_ADDR-1:0]-lbuf_raddr[LBUF_ADDR-1:0])>=LBUF_DEPTH-ALERT_DEPTH);
    end

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            lbuf_rvalid <= 1'b0;
        end
        else begin
            lbuf_rvalid <= (lbuf_ren | lbuf_reuse_ren) & !lbuf_empty;
        end
    end    

    // =============================================================================
    // Weight Memory Interface

    reg     [WMEM_ADDR-1:0]     wmem_waddr;
    reg     [WMEM_ADDR-1:0]     wmem_raddr;

    // 1. Write Channel:
    //      1.1 GBUS -> WMEM for Weight Loading
    always @(*) begin
        wmem_waddr = gbus_addr[WMEM_ADDR-1:0];
        wmem_wen   = gbus_wen && ~gbus_addr[GBUS_ADDR-1]; //ask Guanchen about this
        wmem_wdata = gbus_wdata;
    end

    // 2. Read Channel:
    //      2.1 WMEM -> GBUS  for Weight Check (Debugging)
    //      2.2 WMEM -> MAC   for on-core AxW
    //      2.3 WMEM -> CLINK for off-core AxW (Solved in CLINK Bundle)
    always @(*) begin
        wmem_ren = (gbus_ren && ~gbus_addr[GBUS_ADDR-1]) || (cmem_ren && ~cmem_raddr[GBUS_ADDR-1]);
        if (gbus_ren && ~gbus_addr[GBUS_ADDR-1]) begin // WMEM -> GBUS
            wmem_raddr = gbus_addr[WMEM_ADDR-1:0];
        end
        else begin // WMEM -> MAC
            wmem_raddr = cmem_raddr[WMEM_ADDR-1:0];
        end
    end

    // 3. WMEM_ADDR W/R Selection
    always @(*) begin
        if (wmem_wen) begin // Write
            wmem_addr = wmem_waddr;
        end
        else begin // Read
            wmem_addr = wmem_raddr;
        end
    end

    // =============================================================================
    // KV Cache Interface

    reg     [CACHE_ADDR-1:0]    cache_waddr;
    reg     [CACHE_ADDR-1:0]    cache_raddr;

    // 1. Write Channel:
    //      1.1 GBUS -> KV Cache
    //      1.2 Value Vector from MAC -> KV Cache
    always @(*) begin
        cache_wen = (gbus_wen && gbus_addr[GBUS_ADDR-1]) || (cmem_wen && cmem_waddr[GBUS_ADDR-1]); //ask Guanchen: will always write global bus data to cache even if cache_wen = 0
        if (cmem_wen && cmem_waddr[GBUS_ADDR-1]) begin // GBUS -> KV Cache
            cache_waddr = cmem_waddr[CACHE_ADDR-1:0];
            cache_wdata = cmem_wdata;
        end
        else begin // MAC -> KV Cache
            cache_waddr = gbus_addr[CACHE_ADDR-1:0];
            cache_wdata = gbus_wdata;
        end
    end

    // 2. Read Channel:
    //      2.1 KV Cache -> GBUS  for Key/Value Check (Debugging)
    //      2.2 KV Cache -> MAC   for On-Core QxK/PxV
    //      2.3 KV Cache -> CLINK for Off-Core QxK/PxV (Solved in CLINK Bundle)
    always @(*) begin
        cache_ren = (gbus_ren && gbus_addr[GBUS_ADDR-1]) || (cmem_ren && cmem_raddr[GBUS_ADDR-1]);
        if (gbus_ren && gbus_addr[GBUS_ADDR-1]) begin // KV Cache -> GBUS
            cache_raddr = gbus_addr[CACHE_ADDR-1:0];
        end
        else begin // KV Cache -> MAC
            cache_raddr = cmem_raddr[CACHE_ADDR-1:0];
        end
    end

    // 3. CACHE_ADDR W/R Selection
    always @(*) begin
        if (cache_wen) begin // Write
            cache_addr = cache_waddr;
        end
        else begin // Read
            cache_addr = cache_raddr;
        end
    end

    // =============================================================================
    // GBUS Read Channel

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            gbus_rvalid <= 1'b0;
        end
        else begin
            gbus_rvalid <= gbus_ren;
        end
    end

    always @(*) begin
        if (gbus_rvalid && cache_rvalid) begin // KV Cache -> GBUS
            gbus_rdata = cache_rdata;
        end
        else begin // WMEM -> GBUS
            gbus_rdata = wmem_rdata;
        end
    end

    // =============================================================================
    // Core-to-Core Link Channel

    // 1. Write Channel: CLINK -> Core
    reg     [GBUS_DATA-1:0] clink_reg;
    reg                     clink_reg_valid;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            clink_reg <= 'd0;
        end
        else if (clink_wen) begin
            clink_reg <= clink_wdata;
        end
    end

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            clink_reg_valid <= 1'b0;
        end
        else begin
            clink_reg_valid <= clink_wen;
        end
    end

    // 2. Read Channel: WMEM/Cache/CLINK -> CLINK
    reg                     cmem_rvalid;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            cmem_rvalid <= 1'b0;
        end
        else begin
            cmem_rvalid <= cmem_ren;
        end
    end

    always @(*) begin
        if (clink_enable) begin // Enable CLINK
            clink_rvalid = clink_reg_valid || cmem_rvalid;
        end
        else begin // Disable CLINK
            clink_rvalid = 1'b0;
        end
    end

    always @(*) begin
        if (clink_reg_valid) begin // Core-(i) CLINK -> Core-(i+1) CLINK
            clink_rdata = clink_reg;
        end
        else if (cache_rvalid && cmem_rvalid) begin // Core-(i) KV Cache -> CLINK for Core-(i+1)
            clink_rdata = cache_rdata;
        end
        else begin // Core-(i) WMEM -> CLINK for Core-(i+1)
            clink_rdata = wmem_rdata;
        end
    end

    // =============================================================================
    // LBUF Write Channel: Series to Parallel

    align_s2p_lbuf lbuf_s2p (
        .clk                    (clk),
        .rstn                    (rstn),
        .idata                  (clink_rdata),
        .idata_valid            (clink_rvalid || cmem_rvalid),
        .odata                  (lbuf_wdata),
        .odata_valid            (lbuf_wen)
    );
endmodule 

module align_s2p_lbuf #(
    parameter LBUF_DATA = 64,
    parameter GBUS_DATA = 64
    )(
    input                       clk,
    input                       rstn, 
    input       [GBUS_DATA-1:0] idata,
    input                       idata_valid,
    output  reg [LBUF_DATA-1:0] odata,
    output  reg                 odata_valid
);
    localparam  REG_NUM = LBUF_DATA / GBUS_DATA;
    localparam  ADDR_BIT = $clog2(REG_NUM+1);
    reg     [GBUS_DATA-1:0] regfile [0:REG_NUM-1];
    reg     [ADDR_BIT-1:0]  regfile_addr;           
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            regfile_addr <= 'd0;
        end else if (idata_valid) begin
            regfile_addr <= (regfile_addr + 1'b1)%REG_NUM;
        end
    end
    always @(posedge clk) begin
        if (idata_valid) begin
            regfile[regfile_addr] <= idata;
        end
    end
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            odata_valid <= 1'b0;
        end else begin
            if ((regfile_addr==REG_NUM-1) && idata_valid) begin
                odata_valid <= 1'b1;
            end else begin
                odata_valid <= 1'b0;
            end
        end
    end
    genvar i;
    generate
        for (i = 0; i < REG_NUM; i = i + 1) begin:gen_pal
            always @(*) begin
                odata[i*GBUS_DATA+:GBUS_DATA] = regfile[i];
            end
        end
    endgenerate    
endmodule

module mem_sp_wmem #(
    parameter WMEM_DEPTH = 512,
    parameter GBUS_DATA = 64
)(
    input                       clk,
    input       [$clog2(WMEM_DEPTH)-1:0]  addr,
    input                       wen,
    input       [GBUS_DATA-1:0]  wdata,
    input                       ren,
    output  reg [GBUS_DATA-1:0]  rdata
);
    reg [GBUS_DATA-1:0]  mem [0:WMEM_DEPTH-1];
    always @(posedge clk) begin
        if (wen) begin
            mem[addr] <= wdata;
        end
    end
    always @(posedge clk) begin
        if (ren) begin
            rdata <= mem[addr];
        end
    end
endmodule

module mem_sp_cache #(
    parameter CACHE_DEPTH = 256,
    parameter GBUS_DATA = 64
)(
    input                       clk,
    input       [$clog2(CACHE_DEPTH)-1:0]  addr,
    input                       wen,
    input       [GBUS_DATA-1:0]  wdata,
    input                       ren,
    output  reg [GBUS_DATA-1:0]  rdata
);
    reg [GBUS_DATA-1:0]  mem [0:CACHE_DEPTH-1];
    always @(posedge clk) begin
        if (wen) begin
            mem[addr] <= wdata;
        end
    end
    always @(posedge clk) begin
        if (ren) begin
            rdata <= mem[addr];
        end
    end
endmodule

module mem_dp_lbuf #(
    parameter   LBUF_DATA = 64,
    parameter   LBUF_DEPTH = 64,
    parameter   ADDR_BIT = $clog2(64)
)(
    // Global Signals
    input                       clk,

    // Data Signals
    input       [ADDR_BIT-1:0]  waddr,
    input                       wen,
    input       [LBUF_DATA-1:0]  wdata,
    input       [ADDR_BIT-1:0]  raddr,
    input                       ren,
    output  reg [LBUF_DATA-1:0]  rdata
);

    // 1, Memory initialization
    reg [LBUF_DATA-1:0]  mem [0:LBUF_DEPTH-1];

    // 2. Write channel
    always @(posedge clk) begin
        if (wen) begin
            mem[waddr] <= wdata;
        end
    end

    // 3. Read channel
    always @(posedge clk) begin
        if (ren) begin
            rdata <= mem[raddr];
        end
    end
    
endmodule

/////////////////////////////Core Buf////////////////////////////////
module core_buf #(
    parameter ABUF_DATA = 64,
    parameter ABUF_ADDR = $clog2(64),
    parameter ABUF_DEPTH = 64,
    parameter ALERT_DEPTH = 3,
    parameter GBUS_DATA = 64
)(
    // Global Signals
    input                       clk,
    input                       rstn,

    // Channel - Core-to-Core Link
    input       [GBUS_DATA-1:0] clink_wdata,
    input                       clink_wen,
    output      [GBUS_DATA-1:0] clink_rdata,
    output                      clink_rvalid,

    // Channel - Activation Buffer for MAC Operation
    //input                     abuf_mux,           // Annotate for Double-Buffering ABUF
    //input       [ABUF_ADDR-1:0] abuf_waddr,
    //input       [ABUF_ADDR-1:0] abuf_raddr,
    input                       abuf_ren,
    output      [ABUF_DATA-1:0] abuf_rdata,
    output  reg                 abuf_rvalid,
    output reg                  abuf_empty,
        output reg                  abuf_reuse_empty,
    output reg                  abuf_full,
    //for activation reuse
    input                       abuf_reuse_ren, //reuse pointer logic, when enable
    input                       abuf_reuse_rst,  //reuse reset logic, when first round of reset is finished, reset reuse pointer to current normal read pointer value

    output reg                  abuf_almost_full
    );

    // =============================================================================
    // Memory Instantization: Dual-Port or Double-Buffering ABUF
    // TODO: Design Exploration for DP/DB and SRAM/REGFILE/DFF ABUF
    wire    [ABUF_DATA-1:0]     abuf_wdata;
    wire    [ABUF_DATA-1:0]     abuf_rdata_mem;
    wire                        abuf_wen;
    reg    [ABUF_ADDR:0]          abuf_waddr;
    reg    [ABUF_ADDR:0]          abuf_raddr;
    reg     [ABUF_ADDR:0]       reuse_raddr; //for reuse pointer.
    reg    [ABUF_ADDR-1:0]     abuf_raddr_mux;
    assign abuf_raddr_mux= abuf_reuse_ren ? reuse_raddr[ABUF_ADDR-1:0] : abuf_raddr[ABUF_ADDR-1:0];

    mem_dp_abuf abuf_inst (
        .clk                    (clk),
        .waddr                  (abuf_waddr[ABUF_ADDR-1:0]),
        .wen                    (abuf_wen),
        .wdata                  (abuf_wdata),
        .raddr                  (abuf_raddr[ABUF_ADDR-1:0]),
        .ren                    (abuf_ren),
        .rdata                  (abuf_rdata)
    );

    always @(posedge clk or negedge rstn) begin
        if(~rstn)begin
            abuf_raddr <= '0;
            abuf_waddr <= '0;
            reuse_raddr <= '0;
        end else begin
            if(abuf_ren & abuf_wen) begin
                abuf_raddr <= abuf_raddr + 1;
                abuf_waddr <= abuf_waddr + 1;
                reuse_raddr<= reuse_raddr+ 1;
            end else if(abuf_ren & ~abuf_empty) begin
                abuf_raddr <= abuf_raddr + 1;
                reuse_raddr<= reuse_raddr+ 1;
            end else if(abuf_wen & ~abuf_full) begin
                abuf_waddr <= abuf_waddr + 1;
            end

            if(abuf_reuse_ren & abuf_wen & ~abuf_reuse_rst) begin
                reuse_raddr<= reuse_raddr+ 1;
                abuf_waddr <= abuf_waddr + 1;
            end else if(abuf_reuse_ren & abuf_wen & abuf_reuse_rst) begin
                reuse_raddr<= abuf_raddr;
                abuf_waddr <= abuf_waddr + 1;
            end 
            else if(abuf_reuse_ren & ~abuf_empty & ~abuf_reuse_rst) begin
                reuse_raddr<= reuse_raddr+ 1;
            end else if(abuf_reuse_ren & ~abuf_empty & abuf_reuse_rst) begin
                reuse_raddr<= abuf_raddr;
            end
        end
    end

    assign abuf_empty = (abuf_raddr == abuf_waddr);
    assign abuf_reuse_empty = (reuse_raddr == abuf_waddr);
    assign abuf_full = (abuf_raddr[ABUF_ADDR] ^ abuf_waddr[ABUF_ADDR]) & //should abuf_raddr[ABUF_ADDR] be  at [ABUF_ADDR-1] instead?
        (abuf_raddr[ABUF_ADDR-1:0] == abuf_waddr[ABUF_ADDR-1:0]);
    assign abuf_rdata = abuf_rdata_mem;

    always@(*) begin
        if(abuf_raddr[ABUF_ADDR] ^ abuf_waddr[ABUF_ADDR])
            abuf_almost_full=((abuf_raddr[ABUF_ADDR-1:0]-abuf_waddr[ABUF_ADDR-1:0])<=ALERT_DEPTH);
        else
            abuf_almost_full=((abuf_waddr[ABUF_ADDR-1:0]-abuf_raddr[ABUF_ADDR-1:0])>=ABUF_DEPTH-ALERT_DEPTH);
    end
    

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            abuf_rvalid <= 1'b0;
        end
        else begin
            abuf_rvalid <= (abuf_ren | abuf_reuse_ren) & !abuf_empty;
        end
    end

    // =============================================================================
    // Core-to-Core Link Channel

    // 1. Write Channel: CLINK -> Core
    reg     [GBUS_DATA-1:0]     clink_reg;
    reg                         clink_reg_valid;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            clink_reg <= 'd0;
        end
        else if (clink_wen) begin
            clink_reg <= clink_wdata;
        end
    end

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            clink_reg_valid <= 1'b0;
        end
        else begin
            clink_reg_valid <= clink_wen;
        end
    end

    // 2. Read Channel: Core -> CLINK
    assign  clink_rdata  = clink_reg;
    assign  clink_rvalid = clink_reg_valid;

    // =============================================================================
    // ABUF Write Channel: Series to Parallel

    align_s2p_abuf abuf_s2p (
        .clk                    (clk),
        .rstn                    (rstn),
        .idata                  (clink_reg),
        .idata_valid            (clink_reg_valid),
        .odata                  (abuf_wdata),
        .odata_valid            (abuf_wen)
    );

endmodule 

module align_s2p_abuf #(
    parameter ABUF_DATA = 64,
    parameter GBUS_DATA = 64
)(
    input                       clk,
    input                       rstn, 
    input       [GBUS_DATA-1:0] idata,
    input                       idata_valid,
    output  reg [ABUF_DATA-1:0] odata,
    output  reg                 odata_valid
);
    localparam  REG_NUM = ABUF_DATA / GBUS_DATA;
    localparam  ADDR_BIT = $clog2(REG_NUM+1);
    reg     [GBUS_DATA-1:0] regfile [0:REG_NUM-1];
    reg     [ADDR_BIT-1:0]  regfile_addr;           
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            regfile_addr <= 'd0;
        end else if (idata_valid) begin
            regfile_addr <= (regfile_addr + 1'b1)%REG_NUM;
        end
    end
    always @(posedge clk) begin
        if (idata_valid) begin
            regfile[regfile_addr] <= idata;
        end
    end
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            odata_valid <= 1'b0;
        end else begin
            if ((regfile_addr==REG_NUM-1) && idata_valid) begin
                odata_valid <= 1'b1;
            end else begin
                odata_valid <= 1'b0;
            end
        end
    end
    genvar i;
    generate
        for (i = 0; i < REG_NUM; i = i + 1) begin:gen_pal
            always @(*) begin
                odata[i*GBUS_DATA+:GBUS_DATA] = regfile[i];
            end
        end
    endgenerate    
endmodule

module mem_dp_abuf #(
    parameter   ABUF_DATA = 64,
    parameter   ABUF_DEPTH = 64,
    parameter   ADDR_BIT = $clog2(64)
)(
    // Global Signals
    input                       clk,

    // Data Signals
    input       [ADDR_BIT-1:0]  waddr,
    input                       wen,
    input       [ABUF_DATA-1:0]  wdata,
    input       [ADDR_BIT-1:0]  raddr,
    input                       ren,
    output  reg [ABUF_DATA-1:0]  rdata
);

    // 1, Memory initialization
    reg [ABUF_DATA-1:0]  mem [0:ABUF_DEPTH-1];

    // 2. Write channel
    always @(posedge clk) begin
        if (wen) begin
            mem[waddr] <= wdata;
        end
    end

    // 3. Read channel
    always @(posedge clk) begin
        if (ren) begin
            rdata <= mem[raddr];
        end
    end
    
endmodule


/////////////////////////////Core Mac/////////////////////////////
module core_mac #(
    parameter MAC_NUM = 8,
    parameter IDATA_BIT = 8,
    parameter MAC_ODATA_BIT = 16+$clog2(8)
)(
    // Global Signals
    input                               clk,
    input                               rstn,

    // Data Signals
    input       [IDATA_BIT*MAC_NUM-1:0] idataA,
    input       [IDATA_BIT*MAC_NUM-1:0] idataB,
    input                               idata_valid,
    output      [MAC_ODATA_BIT-1:0]         odata,
    output                              odata_valid
);
    // Multiplication
    wire    [IDATA_BIT*2*MAC_NUM-1:0]   product;
    wire                                product_valid;

    mul_line mul_inst (
        .clk                            (clk),
        .rstn                            (rstn),
        .idataA                         (idataA),
        .idataB                         (idataB),
        .idata_valid                    (idata_valid),
        .odata                          (product),
        .odata_valid                    (product_valid)
    );
    // Addition
    adder_tree adt_inst (
        .clk                            (clk),
        .rstn                            (rstn),
        .idata                          (product),
        .idata_valid                    (product_valid),
        .odata                          (odata),
        .odata_valid                    (odata_valid)
    );  

endmodule

module mul_line #(
    parameter MAC_NUM = 8,
    parameter IDATA_BIT = 8,
    parameter MUL_ODATA_BIT = 16
)(
    // Global Signals
    input                               clk,
    input                               rstn,

    // Data Signals
    input       [IDATA_BIT*MAC_NUM-1:0] idataA,
    input       [IDATA_BIT*MAC_NUM-1:0] idataB,
    input                               idata_valid,
    output  reg [MUL_ODATA_BIT*MAC_NUM-1:0] odata,
    output  reg                         odata_valid
);

    // Input Gating
    reg     [IDATA_BIT-1:0] idataA_reg  [0:MAC_NUM-1];
    reg     [IDATA_BIT-1:0] idataB_reg  [0:MAC_NUM-1];

    genvar i;
    generate
        for (i = 0; i < MAC_NUM; i = i + 1) begin: gen_mul_input
            always @(posedge clk or negedge rstn) begin
                if (!rstn) begin
                    idataA_reg[i] <= 'd0;
                    idataB_reg[i] <= 'd0;
                end
                else if (idata_valid) begin
                    idataA_reg[i] <= idataA[i*IDATA_BIT+:IDATA_BIT];
                    idataB_reg[i] <= idataB[i*IDATA_BIT+:IDATA_BIT];
                end
            end
        end
    endgenerate

    // Mutiplication
    wire    [MUL_ODATA_BIT-1:0] product [0:MAC_NUM-1];

    generate 
        for (i = 0; i < MAC_NUM; i = i + 1) begin: gen_mul
            //$display(gen_mul);
            mul_int mul_inst (
                .idataA                 (idataA_reg[i]), 
                .idataB                 (idataB_reg[i]),
                .odata                  (product[i])
            );
        end
    endgenerate
    // Output
    generate
        for (i = 0; i < MAC_NUM; i = i + 1) begin: gen_mul_output
            always @(*) begin
                odata[i*MUL_ODATA_BIT+:MUL_ODATA_BIT] = product[i]; 
            end
        end
    endgenerate

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            odata_valid <= 'd0;
        end
        else begin
            odata_valid <= idata_valid;
        end
    end

endmodule

module mul_int #(
    parameter IDATA_BIT = 8,
    parameter MUL_ODATA_BIT = 16
)(
    input       [IDATA_BIT-1:0] idataA,
    input       [IDATA_BIT-1:0] idataB,
    output      [MUL_ODATA_BIT-1:0] odata    
);
    reg signed  [MUL_ODATA_BIT-1:0] odata_comb;
    always @(*) begin
        odata_comb = $signed(idataA) * $signed(idataB);
    end
    assign  odata = odata_comb;
endmodule

module adder_tree #(
    parameter ADD_IDATA_BIT = 16,
    parameter ADD_ODATA_BIT = 16 + $clog2(8),
    parameter MAC_NUM = 8
)(
    // Global Signals
    input                               clk,
    input                               rstn,

    // Data Signals
    input       [ADD_IDATA_BIT*MAC_NUM-1:0] idata,
    input                               idata_valid,
    output  reg [ADD_ODATA_BIT-1:0]         odata,
    output  reg                         odata_valid
);

    localparam  STAGE_NUM = $clog2(MAC_NUM);

    // Insert a pipeline every two stages
    // Validation
    genvar i, j;
    generate
        for (i = 0; i < STAGE_NUM; i = i + 1) begin: gen_adt_valid
            reg             add_valid;

            if (i == 0) begin   // Input Stage
                always @(posedge clk or negedge rstn) begin
                    if (!rstn) begin
                        add_valid <= 1'b0;
                    end
                    else begin
                        add_valid <= idata_valid;
                    end
                end
            end
            else if (i % 2 == 1'b0) begin   // Even Stage, Insert a pipeline, Start from 0, 2, 4...
                always @(posedge clk or negedge rstn) begin
                    if (!rstn) begin
                        add_valid <= 1'b0;
                    end
                    else begin
                        add_valid <= gen_adt_valid[i-1].add_valid;
                    end
                end
            end
            else begin  // Odd Stage, Combinational, Start from 1, 3, 5...
                always @(*) begin
                    add_valid = gen_adt_valid[i-1].add_valid;
                end
            end
        end
    endgenerate

    // Adder
    generate
        for (i = 0; i <STAGE_NUM; i = i + 1) begin: gen_adt_stage
            localparam  OUT_BIT = ADD_IDATA_BIT + (i + 1'b1);
            localparam  OUT_NUM = MAC_NUM  >> (i + 1'b1);

            reg     [OUT_BIT-2:0]   add_idata   [0:OUT_NUM*2-1];
            wire    [OUT_BIT-1:0]   add_odata   [0:OUT_NUM-1];

            for (j = 0; j < OUT_NUM; j = j + 1) begin: gen_adt_adder

                // Organize adder inputs
                if (i == 0) begin   // Input Stage
                    always @(posedge clk or negedge rstn) begin
                        if (!rstn) begin
                            add_idata[j*2]   <= 'd0;
                            add_idata[j*2+1] <= 'd0;
                        end
                        else if (idata_valid) begin
                            add_idata[j*2]   <= idata[(j*2+0)*ADD_IDATA_BIT+:ADD_IDATA_BIT];
                            add_idata[j*2+1] <= idata[(j*2+1)*ADD_IDATA_BIT+:ADD_IDATA_BIT];
                        end
                    end
                end
                else if (i % 2 == 0) begin  // Even Stage, Insert a pipeline
                    always @(posedge clk or negedge rstn) begin
                        if (!rstn) begin
                            add_idata[j*2]   <= 'd0;
                            add_idata[j*2+1] <= 'd0;
                        end
                        else if (gen_adt_valid[i-1].add_valid) begin
                            add_idata[j*2]   <= gen_adt_stage[i-1].add_odata[j*2];
                            add_idata[j*2+1] <= gen_adt_stage[i-1].add_odata[j*2+1];
                        end
                    end
                end
                else begin  // Odd Stage, Combinational
                    always @(*) begin
                        add_idata[j*2]   = gen_adt_stage[i-1].add_odata[j*2];
                        add_idata[j*2+1] = gen_adt_stage[i-1].add_odata[j*2+1];
                    end
                end

                // Adder instantization
                add_int #(.ADD_INT_IDATA_BIT(OUT_BIT-1), .ADD_INT_ODATA_BIT(OUT_BIT)) adder_inst (
                    .idataA                 (add_idata[j*2]),
                    .idataB                 (add_idata[j*2+1]),
                    .odata                  (add_odata[j])
                );
            end
        end
    endgenerate

    // Output
    always @(*) begin
        odata       = gen_adt_stage[STAGE_NUM-1].add_odata[0];
        odata_valid = gen_adt_valid[STAGE_NUM-1].add_valid;
    end
endmodule 

module add_int #(
    parameter   ADD_INT_IDATA_BIT = 8,
    parameter   ADD_INT_ODATA_BIT = 9
)(
    // Data Signals
    input       [ADD_INT_IDATA_BIT-1:0] idataA,
    input       [ADD_INT_IDATA_BIT-1:0] idataB,
    output      [ADD_INT_ODATA_BIT-1:0] odata
);

    reg signed  [ADD_INT_ODATA_BIT-1:0] odata_comb;

    always @(*) begin
        odata_comb = $signed(idataA) + $signed(idataB);
    end

    assign  odata = odata_comb;

endmodule

/////////////////////////////////Core Acc///////////////////////////////

module core_acc #(
    parameter ACC_IDATA_BIT = (16+$clog2(8)),
    parameter ODATA_BIT = 16,
    parameter CDATA_BIT = 8
)(
    // Global Signals
    input                       clk,
    input                       rstn,

    // Global Config Signals
    input       [CDATA_BIT-1:0] cfg_acc_num,

    // Data Signals
    input       [ACC_IDATA_BIT-1:0] idata,
    input                       idata_valid,
    output      [ODATA_BIT-1:0] odata,
    output                      odata_valid
);

    // Accumulation Counter
    wire    pre_finish;

    core_acc_ctrl acc_counter_inst (
        .clk                (clk),
        .rstn                (rstn),
        .cfg_acc_num        (cfg_acc_num),
        .psum_valid         (idata_valid),
        .psum_finish        (pre_finish)
    );

    // Accumulation Logic
    core_acc_mac acc_mac_inst (
        .clk                (clk),
        .rstn               (rstn),
        .pre_finish         (pre_finish),

        .idata              (idata),
        .idata_valid        (idata_valid),
        .odata              (odata),
        .odata_valid        (odata_valid)
    );

endmodule


module core_acc_ctrl #(
    parameter   CDATA_BIT = 8
)(
    // Global Signals
    input                       clk,
    input                       rstn,

    // Config Signals
    input       [CDATA_BIT-1:0] cfg_acc_num,

    // Control Signals
    input                       psum_valid,
    output  reg                 psum_finish
);

    parameter   PSUM_IDLE   = 2'b01,
                PSUM_UPDATE = 2'b10;
    reg [1:0]   psum_state;

    reg     [CDATA_BIT-1:0] psum_cnt;
    reg     psum_warmup;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            psum_state  <= 2'b0;
            psum_warmup <= 1'b0;
            psum_cnt    <= 'd0;
            psum_finish <= 1'b0;
        end
        else begin
            case (psum_state)
                PSUM_IDLE: begin
                    psum_cnt    <= 'd0;
                    psum_finish <= 1'b0;
                    psum_warmup <= 1'b0;
                    if (psum_valid) begin
                        psum_state <= PSUM_UPDATE;
                    end
                end
                PSUM_UPDATE: begin
                    if(~psum_warmup) begin
                        if (psum_cnt == cfg_acc_num-1) begin
                            psum_warmup <= 1'b1;
                            if (psum_valid) begin
                                //psum_state  <= PSUM_UPDATE;
                                psum_cnt    <= 'd0;
                                psum_finish <= 1'b1;
                            end
                            else begin
                                //psum_state  <= PSUM_IDLE;
                                psum_cnt    <= 'd0;
                                psum_finish <= 1'b1;
                            end
                        end
                        else if(psum_valid) begin
                            psum_cnt    <= psum_cnt + 1'b1;
                            //psum_finish <= 1'b0;
                            psum_warmup <= 1'b0;
                        end
                    end
                    else begin
                        if (psum_cnt == cfg_acc_num) begin
                            psum_warmup <= psum_warmup;
                            if (psum_valid) begin
                                //psum_state  <= PSUM_UPDATE;
                                psum_cnt    <= 'd0;
                                psum_finish <= 1'b1;
                            end
                            else begin
                                //psum_state  <= PSUM_IDLE;
                                psum_cnt    <= 'd0;
                                psum_finish <= 1'b1;
                            end
                        end
                        else if(psum_valid) begin
                            psum_cnt    <= psum_cnt + 1'b1;
                            //psum_finish <= 1'b0;
                            psum_warmup <= psum_warmup;
                        end
                    end

                    //state transition
                    if(psum_cnt ==0) begin
                        if(psum_valid) begin
                            psum_state <= PSUM_UPDATE;
                            psum_finish <= 1'b0;
                        end
                        else if(psum_finish) begin
                            psum_state <= PSUM_IDLE;
                            psum_finish <= 1'b0;
                        end
                    end
                end
                default: begin
                    psum_state <= PSUM_IDLE;
                    psum_warmup <= psum_warmup;
                end
            endcase
        end
    end

endmodule


module core_acc_mac #(
    parameter ACC_IDATA_BIT = (16+$clog2(8)),
    parameter ODATA_BIT = 16
)(
    // Global Signals
    input                       clk,
    input                       rstn,

    // Control Signals
    input                       pre_finish,

    // Data Signals
    input       [ACC_IDATA_BIT-1:0] idata,
    input                       idata_valid,
    output  reg [ODATA_BIT-1:0] odata,
    output  reg                 odata_valid
);

    // Input Gating
    reg signed  [ACC_IDATA_BIT-1:0] idata_reg;
    reg                         idata_valid_reg;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            idata_reg <= 'd0;
        end
        else if (idata_valid) begin
            idata_reg <= idata;
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

    // Accumulation
    reg signed  [ODATA_BIT-1:0] acc_reg;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            acc_reg <= 'd0;
        end
        else if (pre_finish) begin
            acc_reg <= 'd0;
        end
        else if (idata_valid_reg) begin
            acc_reg <= idata_reg + acc_reg;
        end
    end

    // Output and Valid
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            odata <= 'd0;
        end
        else if (pre_finish) begin
            odata <= idata_reg + acc_reg;
        end
    end

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            odata_valid <= 1'b0;
        end
        else begin
            odata_valid <= pre_finish;
        end
    end

endmodule 
////////////////////////////////Core Quant////////////////////////////////
module core_quant #(
    parameter QUANT_IDATA_BIT = 16,
    parameter QUANT_ODATA_BIT = 8
)(
    // Global Signals
    input                       clk,
    input                       rstn,

    // Global Config Signals
    input       [QUANT_IDATA_BIT-1:0] cfg_quant_scale,
    input       [QUANT_IDATA_BIT-1:0] cfg_quant_bias,
    input       [QUANT_IDATA_BIT-1:0] cfg_quant_shift,

    // Data Signals
    input       [QUANT_IDATA_BIT-1:0] idata,
    input                       idata_valid,
    output  reg [QUANT_ODATA_BIT-1:0] odata,
    output  reg                 odata_valid
);

    // Input Gating
    // Causing the input from the accumulator register, no pipeline needed here

    // Quantize: Scale x Input + Bias
    reg signed  [QUANT_IDATA_BIT*2-1:0]   quantized_product,quantized_bias;
    reg                             quantized_product_valid,quantized_shift_valid,quantized_round_valid,quantized_overflow_valid,quantized_bias_valid;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            quantized_product <= 'd0;
        end
        else if (idata_valid) begin
            quantized_product <= $signed(idata) * $signed(cfg_quant_scale);
        end
    end

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            quantized_product_valid <= 1'b0;
        end
        else begin
            quantized_product_valid <= idata_valid;
        end
    end

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            quantized_bias <= 'd0;
        end
        else if (quantized_product_valid) begin
            quantized_bias <= $signed(quantized_product) + $signed(cfg_quant_bias);
        end
    end

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            quantized_bias_valid <= 1'b0;
        end
        else begin
            quantized_bias_valid <= quantized_product_valid;
        end
    end

    // Quantize: Shift and Round
    reg signed  [QUANT_IDATA_BIT*2-1:0]   quantized_shift,quantized_shift_reg;
    reg signed  [QUANT_IDATA_BIT*2-1:0]   quantized_round,quantized_round_reg;

    always @(*) begin
        quantized_shift = quantized_bias >> cfg_quant_shift;
    end
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            quantized_shift_reg <= 'd0;
        end
        else if(quantized_bias_valid)begin
            quantized_shift_reg <= quantized_shift;
        end
    end
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            quantized_shift_valid <= 1'b0;
        end
        else begin
            quantized_shift_valid <= quantized_bias_valid;
        end
    end

    always @(*) begin
        quantized_round = $signed(quantized_shift_reg[QUANT_IDATA_BIT*2-1:1]) + 
        $signed({quantized_shift_reg[QUANT_IDATA_BIT*2-1], quantized_shift_reg[0]});
    end
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            quantized_round_reg <= 'd0;
        end
        else if(quantized_shift_valid)begin
            quantized_round_reg <= quantized_round;
        end
    end
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            quantized_round_valid <= 1'b0;
        end
        else begin
            quantized_round_valid <= quantized_shift_valid;
        end
    end

    // Quantize: Detect Overflow
    reg         [QUANT_ODATA_BIT-1:0]     quantized_overflow;

    always @(*) begin
        if ((quantized_round_reg[QUANT_IDATA_BIT*2-1] ^ (&quantized_round_reg[QUANT_IDATA_BIT*2-2:QUANT_ODATA_BIT-1])) ||
            (quantized_round_reg[QUANT_IDATA_BIT*2-1] ^ (|quantized_round_reg[QUANT_IDATA_BIT*2-2:QUANT_ODATA_BIT-1]))) begin
            quantized_overflow = {quantized_round_reg[QUANT_IDATA_BIT*2-1], 
                                  {(QUANT_ODATA_BIT-1){~quantized_round_reg[QUANT_IDATA_BIT*2-1]}}};
        end
        else begin
            quantized_overflow = {quantized_round_reg[QUANT_IDATA_BIT*2-1], quantized_round_reg[QUANT_ODATA_BIT-2:0]};
        end
    end

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            odata <= 'd0;
        end
        else if (quantized_round_valid) begin
            odata <= quantized_overflow;
        end
    end

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            odata_valid <= 'd0;
        end
        else begin
            odata_valid <= quantized_round_valid;
        end
    end
endmodule

