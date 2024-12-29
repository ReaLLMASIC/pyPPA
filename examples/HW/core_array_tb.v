`timescale 1ns / 1ps

module core_array_tb;

    // Parameters
    parameter HNUM = ${num_head}; // Set a default value or replace with `${num_head}`
    parameter VNUM = 8;

    parameter GBUS_DATA = 64;
    parameter GBUS_ADDR = 12;

    parameter LBUF_DEPTH = 64;
    parameter LBUF_DATA = 64;
    parameter LBUF_ADDR = $clog2(LBUF_DEPTH);

    parameter CDATA_BIT = 8;

    parameter ODATA_BIT = 16;
    parameter IDATA_BIT = 8;
    parameter MAC_NUM = 8;

    parameter WMEM_DEPTH = 512; 
    parameter CACHE_DEPTH = 256;

    // Clock and reset
    reg clk;
    reg rstn;

    // Configuration inputs
    reg [ODATA_BIT-1:0] cfg_quant_scale;
    reg [ODATA_BIT-1:0] cfg_quant_bias;
    reg [ODATA_BIT-1:0] cfg_quant_shift;
    reg [CDATA_BIT-1:0] cfg_consmax_shift;
    reg [HNUM-1:0][CDATA_BIT-1:0] cfg_acc_num;

    // Global Bus signals
    reg [HNUM-1:0][GBUS_ADDR-1:0] in_GBUS_ADDR;
    reg [HNUM * VNUM - 1:0] gbus_wen;
    reg [HNUM-1:0][GBUS_DATA-1:0] gbus_wdata;
    reg [HNUM * VNUM - 1:0] gbus_ren;
    wire [HNUM-1:0][GBUS_DATA-1:0] gbus_rdata;
    wire [HNUM * VNUM - 1:0] gbus_rvalid;

    // Vertical and horizontal links
    reg vlink_enable;
    reg [VNUM-1:0][GBUS_DATA-1:0] vlink_wdata;
    reg [VNUM-1:0] vlink_wen;
    wire [VNUM-1:0][GBUS_DATA-1:0] vlink_rdata;
    wire [VNUM-1:0] vlink_rvalid;

    reg [HNUM-1:0][GBUS_DATA-1:0] hlink_wdata;
    reg [HNUM-1:0] hlink_wen;
    wire [HNUM-1:0][GBUS_DATA-1:0] hlink_rdata;
    wire [HNUM-1:0] hlink_rvalid;

    // Core memory and local buffer signals
    reg [HNUM-1:0][VNUM-1:0][GBUS_ADDR-1:0] cmem_waddr;
    reg [HNUM-1:0][VNUM-1:0] cmem_wen;
    reg [HNUM-1:0][VNUM-1:0][GBUS_ADDR-1:0] cmem_raddr;
    reg [HNUM-1:0][VNUM-1:0] cmem_ren;

    wire [HNUM-1:0][VNUM-1:0] lbuf_empty;
    wire [HNUM-1:0][VNUM-1:0] lbuf_reuse_empty;
    reg [HNUM-1:0][VNUM-1:0] lbuf_reuse_ren;
    reg [HNUM-1:0][VNUM-1:0] lbuf_reuse_rst;
    wire [HNUM-1:0][VNUM-1:0] lbuf_full;
    wire [HNUM-1:0][VNUM-1:0] lbuf_almost_full;
    reg [HNUM-1:0][VNUM-1:0] lbuf_ren;

    wire [HNUM-1:0][VNUM-1:0] abuf_empty;
    wire [HNUM-1:0][VNUM-1:0] abuf_reuse_empty;
    reg [HNUM-1:0][VNUM-1:0] abuf_reuse_ren;
    reg [HNUM-1:0][VNUM-1:0] abuf_reuse_rst;
    wire [HNUM-1:0][VNUM-1:0] abuf_full;
    wire [HNUM-1:0][VNUM-1:0] abuf_almost_full;
    reg [HNUM-1:0][VNUM-1:0] abuf_ren;

    // Instantiate core_array
    core_array dut (
    .clk(clk),
    .rstn(rstn),
    .cfg_quant_scale(cfg_quant_scale),
    .cfg_quant_bias(cfg_quant_bias),
    .cfg_quant_shift(cfg_quant_shift),
    .cfg_consmax_shift(cfg_consmax_shift),
    .cfg_acc_num(cfg_acc_num),
    .in_GBUS_ADDR(in_GBUS_ADDR),
    .gbus_wen(gbus_wen),
    .gbus_wdata(gbus_wdata),
    .gbus_ren(gbus_ren),
    .gbus_rdata(gbus_rdata),
    .gbus_rvalid(gbus_rvalid),
    .vlink_enable(vlink_enable),
    .vlink_wdata(vlink_wdata),
    .vlink_wen(vlink_wen),
    .vlink_rdata(vlink_rdata),
    .vlink_rvalid(vlink_rvalid),
    .hlink_wdata(hlink_wdata),
    .hlink_wen(hlink_wen),
    .hlink_rdata(hlink_rdata),
    .hlink_rvalid(hlink_rvalid),
    .cmem_waddr(cmem_waddr),
    .cmem_wen(cmem_wen),
    .cmem_raddr(cmem_raddr),
    .cmem_ren(cmem_ren),
    .lbuf_empty(lbuf_empty),
    .lbuf_reuse_empty(lbuf_reuse_empty),
    .lbuf_reuse_ren(lbuf_reuse_ren),
    .lbuf_reuse_rst(lbuf_reuse_rst),
    .lbuf_full(lbuf_full),
    .lbuf_almost_full(lbuf_almost_full),
    .lbuf_ren(lbuf_ren),
    .abuf_empty(abuf_empty),
    .abuf_reuse_empty(abuf_reuse_empty),
    .abuf_reuse_ren(abuf_reuse_ren),
    .abuf_reuse_rst(abuf_reuse_rst),
    .abuf_full(abuf_full),
    .abuf_almost_full(abuf_almost_full),
    .abuf_ren(abuf_ren)
);

    always #${clk_period / 2} clk = ~clk;

    // Test stimulus
    initial begin
        $dumpfile("core_array_tb.vcd");
        $dumpvars(0, core_array_tb);

        // Initialize inputs
        rstn = 0;
        cfg_quant_scale = 0;
        cfg_quant_bias = 0;
        cfg_quant_shift = 0;
        cfg_consmax_shift = 0;
        cfg_acc_num = 0;
        in_GBUS_ADDR = 0;
        gbus_wen = 0;
        gbus_wdata = 0;
        gbus_ren = 0;
        vlink_enable = 0;
        vlink_wdata = 0;
        vlink_wen = 0;
        hlink_wdata = 0;
        hlink_wen = 0;
        cmem_waddr = 0;
        cmem_wen = 0;
        cmem_raddr = 0;
        cmem_ren = 0;
        lbuf_reuse_ren = 0;
        lbuf_reuse_rst = 0;
        lbuf_ren = 0;
        abuf_reuse_ren = 0;
        abuf_reuse_rst = 0;
        abuf_ren = 0;

        // Apply reset
        #10 rstn = 1;

        // Test cases
        #10;
        cfg_acc_num = {HNUM{8'hFF}};
        gbus_wen = {HNUM{8'h01}};
        gbus_wdata = {HNUM{64'hDEADBEEFDEADBEEF}};
        gbus_ren = {HNUM{8'h01}};

        #20;
        gbus_wen = 0;
        gbus_ren = 0;

        #100;
        $finish;
    end

endmodule
