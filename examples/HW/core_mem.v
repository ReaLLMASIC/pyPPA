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
`define WMEM_ADDR = $clog2(WMEM_DEPTH)
`define CACHE_DEPTH = 256
`define CACHE_ADDR = $clog2(CACHE_DEPTH)
`define ALERT_DEPTH = 3
module core_mem (
    // Global Signals
    input                       clk,
    input                       rstn,

    // Channel - Global Bus (GBUS) to Access Core Memory (WMEM and KV Cache)
    // Data Upload from (1) Chip Interface and (2) Vector Engine
    input       [`GBUS_ADDR-1:0] gbus_addr,
    input                       gbus_wen,
    input       [`GBUS_DATA-1:0] gbus_wdata,
    input                       gbus_ren,
    output  reg [`GBUS_DATA-1:0] gbus_rdata,
    output  reg                 gbus_rvalid,

    // Channel - Core-to-Core Link (CLINK)
    // Global Config Signals
    input                       clink_enable,
    // No WADDR. The data from neighboring core is sent to MAC directly.
    input       [`GBUS_DATA-1:0] clink_wdata,
    input                       clink_wen,
    // No RADDR. The data to neighboring core is the same as the current operand.
    output  reg [`GBUS_DATA-1:0] clink_rdata,
    output  reg                 clink_rvalid,

    // Channel - Core Memory for MAC Operation
    // Write back results from MAC directly.
    input       [`GBUS_ADDR-1:0] cmem_waddr,         // Assume WMEM_ADDR >= CACHE_ADDR
    input                       cmem_wen,
    input       [`GBUS_DATA-1:0] cmem_wdata,
    // Read data to LBUF. No RDATA, Sent data to LBUF directly in this module.
    input       [`GBUS_ADDR-1:0] cmem_raddr,
    input                       cmem_ren,

    // Channel - Local Memory (LBUF) for MAC Operation
    //input                     lbuf_mux,           // Annotate for Double-Buffering LBUF
    //input       [LBUF_ADDR-1:0] lbuf_waddr,         // No WDATA or WEN. Receive data from CMEM directly in this moduel.
    //input       [LBUF_ADDR-1:0] lbuf_raddr,
    input                       lbuf_ren,
    output      [`LBUF_DATA-1:0] lbuf_rdata,         // To MAC
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
    reg     [`WMEM_ADDR-1:0]     wmem_addr;
    reg                         wmem_wen;
    reg     [`GBUS_DATA-1:0]     wmem_wdata;
    reg                         wmem_ren;
    wire    [`GBUS_DATA-1:0]     wmem_rdata;
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
    reg     [`CACHE_ADDR-1:0]    cache_addr;
    reg                         cache_wen;
    reg     [`GBUS_DATA-1:0]     cache_wdata;
    reg                         cache_ren;
    wire    [`GBUS_DATA-1:0]     cache_rdata;
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
    wire    [`LBUF_DATA-1:0]     lbuf_wdata;     // Series_to_Parallel -> LBUF_WDATA
    wire    [`LBUF_DATA-1:0]     lbuf_rdata_mem;
    wire                        lbuf_wen;
    reg    [`LBUF_ADDR:0]     lbuf_waddr; //was wire before
    reg    [`LBUF_ADDR:0]     lbuf_raddr; //was wire before
    reg    [`LBUF_ADDR:0]       reuse_raddr; //for reuse pointer.
    reg    [`LBUF_ADDR-1:0]     lbuf_raddr_mux;
    assign lbuf_raddr_mux= lbuf_reuse_ren ? reuse_raddr[`LBUF_ADDR-1:0] : lbuf_raddr[`LBUF_ADDR-1:0];
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
    assign lbuf_full = (lbuf_raddr[`LBUF_ADDR] ^ lbuf_waddr[`LBUF_ADDR]) & //should abuf_raddr[LBUF_ADDR] be  at [LBUF_ADDR-1] instead?
        (lbuf_raddr[`LBUF_ADDR-1:0] == lbuf_waddr[`LBUF_ADDR-1:0]);
    assign lbuf_rdata = lbuf_rdata_mem;

    always@(*) begin
        if(lbuf_raddr[`LBUF_ADDR] ^ lbuf_waddr[`LBUF_ADDR])
            lbuf_almost_full=((lbuf_raddr[`LBUF_ADDR-1:0]-lbuf_waddr[`LBUF_ADDR-1:0])<=`ALERT_DEPTH);
        else
            lbuf_almost_full=((lbuf_waddr[`LBUF_ADDR-1:0]-lbuf_raddr[`LBUF_ADDR-1:0])>=`LBUF_DEPTH-`ALERT_DEPTH);
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

    reg     [`WMEM_ADDR-1:0]     wmem_waddr;
    reg     [`WMEM_ADDR-1:0]     wmem_raddr;

    // 1. Write Channel:
    //      1.1 GBUS -> WMEM for Weight Loading
    always @(*) begin
        wmem_waddr = gbus_addr[`WMEM_ADDR-1:0];
        wmem_wen   = gbus_wen && ~gbus_addr[`GBUS_ADDR-1]; //ask Guanchen about this
        wmem_wdata = gbus_wdata;
    end

    // 2. Read Channel:
    //      2.1 WMEM -> GBUS  for Weight Check (Debugging)
    //      2.2 WMEM -> MAC   for on-core AxW
    //      2.3 WMEM -> CLINK for off-core AxW (Solved in CLINK Bundle)
    always @(*) begin
        wmem_ren = (gbus_ren && ~gbus_addr[`GBUS_ADDR-1]) || (cmem_ren && ~cmem_raddr[`GBUS_ADDR-1]);
        if (gbus_ren && ~gbus_addr[`GBUS_ADDR-1]) begin // WMEM -> GBUS
            wmem_raddr = gbus_addr[`WMEM_ADDR-1:0];
        end
        else begin // WMEM -> MAC
            wmem_raddr = cmem_raddr[`WMEM_ADDR-1:0];
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

    reg     [`CACHE_ADDR-1:0]    cache_waddr;
    reg     [`CACHE_ADDR-1:0]    cache_raddr;

    // 1. Write Channel:
    //      1.1 GBUS -> KV Cache
    //      1.2 Value Vector from MAC -> KV Cache
    always @(*) begin
        cache_wen = (gbus_wen && gbus_addr[`GBUS_ADDR-1]) || (cmem_wen && cmem_waddr[`GBUS_ADDR-1]); //ask Guanchen: will always write global bus data to cache even if cache_wen = 0
        if (cmem_wen && cmem_waddr[`GBUS_ADDR-1]) begin // GBUS -> KV Cache
            cache_waddr = cmem_waddr[`CACHE_ADDR-1:0];
            cache_wdata = cmem_wdata;
        end
        else begin // MAC -> KV Cache
            cache_waddr = gbus_addr[`CACHE_ADDR-1:0];
            cache_wdata = gbus_wdata;
        end
    end

    // 2. Read Channel:
    //      2.1 KV Cache -> GBUS  for Key/Value Check (Debugging)
    //      2.2 KV Cache -> MAC   for On-Core QxK/PxV
    //      2.3 KV Cache -> CLINK for Off-Core QxK/PxV (Solved in CLINK Bundle)
    always @(*) begin
        cache_ren = (gbus_ren && gbus_addr[`GBUS_ADDR-1]) || (cmem_ren && cmem_raddr[`GBUS_ADDR-1]);
        if (gbus_ren && gbus_addr[`GBUS_ADDR-1]) begin // KV Cache -> GBUS
            cache_raddr = gbus_addr[`CACHE_ADDR-1:0];
        end
        else begin // KV Cache -> MAC
            cache_raddr = cmem_raddr[`CACHE_ADDR-1:0];
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


module align_s2p_lbuf (
    input                       clk,
    input                       rstn, 
    input       [`GBUS_DATA-1:0] idata,
    input                       idata_valid,
    output  reg [`LBUF_DATA-1:0] odata,
    output  reg                 odata_valid
);
    localparam  REG_NUM = `LBUF_DATA / `GBUS_DATA;
    localparam  ADDR_BIT = $clog2(REG_NUM+1);
    reg     [`GBUS_DATA-1:0] regfile [0:REG_NUM-1];
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
                odata[i*`GBUS_DATA+:`GBUS_DATA] = regfile[i];
            end
        end
    endgenerate    
endmodule

module mem_sp_wmem (
    input                       clk,
    input       [$clog2(`WMEM_DEPTH)-1:0]  addr,
    input                       wen,
    input       [$clog2(`WMEM_DEPTH)-1:0]  wdata,
    input                       ren,
    output  reg [$clog2(`WMEM_DEPTH)-1:0]  rdata
);
    reg [`GBUS_DATA-1:0]  mem [0:`WMEM_DEPTH-1];
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

module mem_sp_cache (
    input                       clk,
    input       [$clog2(`CACHE_DEPTH)-1:0]  addr,
    input                       wen,
    input       [$clog2(`CACHE_DEPTH)-1:0]  wdata,
    input                       ren,
    output  reg [$clog2(`CACHE_DEPTH)-1:0]  rdata
);
    reg [`GBUS_DATA-1:0]  mem [0:`CACHE_DEPTH-1];
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

module mem_sp_lbuf (
    input                       clk,
    input       [$clog2(`LBUF_DEPTH)-1:0]  addr,
    input                       wen,
    input       [$clog2(`LBUF_DEPTH)-1:0]  wdata,
    input                       ren,
    output  reg [$clog2(`LBUF_DEPTH)-1:0]  rdata
);
    reg [`LBUF_DATA-1:0]  mem [0:`LBUF_DEPTH-1];
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
