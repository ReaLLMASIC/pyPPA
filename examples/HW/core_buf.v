`define GBUS_DATA = 64
`define ABUF_DEPTH = 64
`define ABUF_DATA =  64
`define ABUF_ADDR  = $clog2(ABUF_DEPTH)
`define ALERT_DEPTH = 3

module core_buf (
    // Global Signals
    input                       clk,
    input                       rstn,

    // Channel - Core-to-Core Link
    input       [`GBUS_DATA-1:0] clink_wdata,
    input                       clink_wen,
    output      [`GBUS_DATA-1:0] clink_rdata,
    output                      clink_rvalid,

    // Channel - Activation Buffer for MAC Operation
    //input                     abuf_mux,           // Annotate for Double-Buffering ABUF
    //input       [ABUF_ADDR-1:0] abuf_waddr,
    //input       [ABUF_ADDR-1:0] abuf_raddr,
    input                       abuf_ren,
    output      [`ABUF_DATA-1:0] abuf_rdata,
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
    wire    [`ABUF_DATA-1:0]     abuf_wdata;
    wire    [`ABUF_DATA-1:0]     abuf_rdata_mem;
    wire                        abuf_wen;
    reg    [`ABUF_ADDR:0]          abuf_waddr;
    reg    [`ABUF_ADDR:0]          abuf_raddr;
    reg     [`ABUF_ADDR:0]       reuse_raddr; //for reuse pointer.
    reg    [`ABUF_ADDR-1:0]     abuf_raddr_mux;
    assign abuf_raddr_mux= abuf_reuse_ren ? reuse_raddr[`ABUF_ADDR-1:0] : abuf_raddr[`ABUF_ADDR-1:0];

    mem_dp_abuf abuf_inst (
        .clk                    (clk),
        .waddr                  (abuf_waddr[`ABUF_ADDR-1:0]),
        .wen                    (abuf_wen),
        .wdata                  (abuf_wdata),
        .raddr                  (abuf_raddr[`ABUF_ADDR-1:0]),
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
    assign abuf_full = (abuf_raddr[`ABUF_ADDR] ^ abuf_waddr[`ABUF_ADDR]) & //should abuf_raddr[ABUF_ADDR] be  at [ABUF_ADDR-1] instead?
        (abuf_raddr[`ABUF_ADDR-1:0] == abuf_waddr[`ABUF_ADDR-1:0]);
    assign abuf_rdata = abuf_rdata_mem;

    always@(*) begin
        if(abuf_raddr[`ABUF_ADDR] ^ abuf_waddr[`ABUF_ADDR])
            abuf_almost_full=((abuf_raddr[`ABUF_ADDR-1:0]-abuf_waddr[`ABUF_ADDR-1:0])<=`ALERT_DEPTH);
        else
            abuf_almost_full=((abuf_waddr[`ABUF_ADDR-1:0]-abuf_raddr[`ABUF_ADDR-1:0])>=`ABUF_DEPTH-`ALERT_DEPTH);
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
    reg     [`GBUS_DATA-1:0]     clink_reg;
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

module align_s2p_abuf (
    input                       clk,
    input                       rstn, 
    input       [`GBUS_DATA-1:0] idata,
    input                       idata_valid,
    output  reg [`ABUF_DATA-1:0] odata,
    output  reg                 odata_valid
);
    localparam  REG_NUM = `ABUF_DATA / `GBUS_DATA;
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


module mem_sp_abuf (
    input                       clk,
    input       [$clog2(`ABUF_DEPTH)-1:0]  addr,
    input                       wen,
    input       [$clog2(`ABUF_DEPTH)-1:0]  wdata,
    input                       ren,
    output  reg [$clog2(`ABUF_DEPTH)-1:0]  rdata
);
    reg [`ABUF_DATA-1:0]  mem [0:`ABUF_DEPTH-1];
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
