`define HNUM = ${num_head}
`define VNUM = 8
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

module core_array (
    // Global Signals
    input                       clk,
    input                       rstn,
    // Global Config Signals
    // input    CFG_ARR_PACKET  arr_cfg,
	// typedef struct packed {
		// reg       [`ARR_ODATA_BIT-1:0] cfg_quant_scale;//16
		// reg       [`ARR_ODATA_BIT-1:0] cfg_quant_bias;//10
		// reg       [`ARR_ODATA_BIT-1:0] cfg_quant_shift;//2
		// reg       [`ARR_CDATA_BIT-1:0] cfg_consmax_shift;//0

	// } CFG_ARR_PACKET;
	input       [`ODATA_BIT-1:0] cfg_quant_scale,//16
	input       [`ODATA_BIT-1:0] cfg_quant_bias,//10
	input       [`ODATA_BIT-1:0] cfg_quant_shift,//2
	input       [`CDATA_BIT-1:0] cfg_consmax_shift,//0 
	
	
	input    [`HNUM-1:0][`CDATA_BIT-1:0]     cfg_acc_num,
    // Channel - Global Bus to Access Core Memory and MAC Result
    // 1. Write Channel
    //      1.1 Chip Interface -> WMEM for Weight Upload
    //      1.2 Chip Interface -> KV Cache for KV Upload (Just Run Attention Test)
    //      1.3 Vector Engine  -> KV Cache for KV Upload (Run Projection and/or Attention)
    // 2. Read Channel
    //      2.1 WMEM       -> Chip Interface for Weight Check
    //      2.2 KV Cache   -> Chip Interface for KV Checnk
    //      2.3 MAC Result -> Vector Engine  for Post Processing
	input            [`HNUM-1:0][`GBUS_ADDR-1:0]     GBUS_ADDR,
    input            [`HNUM-1:0][`VNUM-1:0]                           gbus_wen,
    input            [`HNUM-1:0][`GBUS_DATA-1:0]     gbus_wdata,     // From Global SRAM for weight loading
    input            [`HNUM-1:0][`VNUM-1:0]                           gbus_ren,
    output   reg   [`HNUM-1:0][`GBUS_DATA-1:0]     gbus_rdata,     // To Chip Interface (Debugging) and Vector Engine (MAC)
    output   reg   [`HNUM-1:0] [`VNUM-1:0]        gbus_rvalid,
    // Channel - Core-to-Core Link
    // Vertical for Weight and Key/Value Propagation
    input                                           vlink_enable,
    input            [`VNUM-1:0][`GBUS_DATA-1:0]     vlink_wdata,
    input            [`VNUM-1:0]                    vlink_wen,
    output   reg   [`VNUM-1:0][`GBUS_DATA-1:0]     vlink_rdata,
    output   reg   [`VNUM-1:0]                    vlink_rvalid,
    // Horizontal for Activation Propagation
    input            [`HNUM-1:0][`GBUS_DATA-1:0]     hlink_wdata,    //hlink_wdata go through reg, to hlink_rdata
    input            [`HNUM-1:0]                    hlink_wen,     
    output   reg   [`HNUM-1:0][`GBUS_DATA-1:0]     hlink_rdata,
    output   reg   [`HNUM-1:0]                    hlink_rvalid,
    // Channel - MAC Operation
    // Core Memory Access for Weight and KV Cache
    //input            CMEM_ARR_PACKET                arr_cmem,
	input 	[`HNUM-1:0][`VNUM-1:0][`GBUS_ADDR-1:0]  cmem_waddr,      // Write Value to KV Cache, G_BUS -> KV Cache, debug.
    input 	[`HNUM-1:0][`VNUM-1:0]    cmem_wen,
    input	[`HNUM-1:0][`VNUM-1:0][`GBUS_ADDR-1:0]  cmem_raddr,
    input	[`HNUM-1:0][`VNUM-1:0]    cmem_ren,
	
    // Local Buffer Access for Weight and KV Cache
    output           [`HNUM-1:0][`VNUM-1:0]        lbuf_empty,
    output           [`HNUM-1:0][`VNUM-1:0]        lbuf_reuse_empty,
    input            [`HNUM-1:0][`VNUM-1:0]        lbuf_reuse_ren, //reuse pointer logic, when enable
    input            [`HNUM-1:0][`VNUM-1:0]        lbuf_reuse_rst,  //reuse reset logic, when first round of reset is finished, reset reuse pointer to current normal read pointer value
    output           [`HNUM-1:0][`VNUM-1:0]        lbuf_full,
    output           [`HNUM-1:0][`VNUM-1:0]        lbuf_almost_full,
    input            [`HNUM-1:0][`VNUM-1:0]        lbuf_ren,
    // Local Buffer access for Activation
    output           [`HNUM-1:0][`VNUM-1:0]        abuf_empty,
    output           [`HNUM-1:0][`VNUM-1:0]        abuf_reuse_empty,
    input            [`HNUM-1:0][`VNUM-1:0]        abuf_reuse_ren, //reuse pointer logic, when enable
    input            [`HNUM-1:0][`VNUM-1:0]        abuf_reuse_rst,  //reuse reset logic, when first round of reset is finished, reset reuse pointer to current normal read pointer value
    output           [`HNUM-1:0][`VNUM-1:0]        abuf_full,
    output           [`HNUM-1:0][`VNUM-1:0]        abuf_almost_full,
    input            [`HNUM-1:0][`VNUM-1:0]        abuf_ren
);

//from spi
//CFG_ARR_PACKET arr_cfg_reg;
	reg       [`ODATA_BIT-1:0] reg_cfg_quant_scale;//16
	reg       [`ODATA_BIT-1:0] reg_cfg_quant_bias;//10
	reg       [`ODATA_BIT-1:0] reg_cfg_quant_shift;//2
	reg       [`CDATA_BIT-1:0] reg_cfg_consmax_shift;//0

always @(posedge clk or negedge rstn) begin
    if(!rstn) begin
	    reg_cfg_quant_scale<={`ODATA_BIT{1'b0}};
	    reg_cfg_quant_bias<={`ODATA_BIT{1'b0}};
	    reg_cfg_quant_shift<={`ODATA_BIT{1'b0}};
	    reg_cfg_consmax_shift<={`ODATA_BIT{1'b0}};
    end
    else begin
        reg_cfg_quant_scale<=reg_cfg_quant_scale;
		reg_cfg_quant_bias<=reg_cfg_quant_bias;
		reg_cfg_quant_shift<=reg_cfg_quant_shift;
		reg_cfg_consmax_shift<=reg_cfg_consmax_shift;
    end
end

	reg [`HNUM-1:0][`VNUM-1:0][`CDATA_BIT-1:0] cfg_acc_num_reg;
integer i, j;
always @(posedge clk or negedge rstn) begin
    if(!rstn) begin
	    cfg_acc_num_reg <= {`HNUM*`VNUM*`CDATA_BIT{1'b0}};
    end
    else begin
	for(i=0; i<`HNUM; i = i+1) begin
	    for(j=0;j<`VNUM;j = j+1) begin
                if(j==0) begin
                    cfg_acc_num_reg[i][0] <= cfg_acc_num[i];
                end
                else begin
                    cfg_acc_num_reg[i][j] <= cfg_acc_num_reg[i][j-1];
                end
            end
        end
    end
end


reg [`HNUM-1:0][`VNUM-1:0][`GBUS_DATA-1:0] vlink_wdata_temp;
reg [`HNUM-1:0][`VNUM-1:0][`GBUS_DATA-1:0] vlink_rdata_temp;
reg [`HNUM-1:0][`VNUM-1:0]   vlink_wen_temp;
reg [`HNUM-1:0][`VNUM-1:0]   vlink_rvalid_temp;

reg [`HNUM-1:0][`VNUM-1:0][`GBUS_DATA-1:0] hlink_wdata_temp;
reg [`HNUM-1:0][`VNUM-1:0][`GBUS_DATA-1:0] hlink_rdata_temp;
reg [`HNUM-1:0][`VNUM-1:0]   hlink_wen_temp;
reg [`HNUM-1:0][`VNUM-1:0]   hlink_rvalid_temp;

reg [`HNUM-1:0][`VNUM-1:0][`GBUS_ADDR-1:0] GBUS_ADDR_temp;
reg [`HNUM-1:0][`VNUM-1:0][`GBUS_DATA-1:0] gbus_wdata_temp;
reg [`HNUM-1:0][`VNUM-1:0][`GBUS_DATA-1:0] gbus_rdata_temp;


always @* begin:hlink_vlink_connection
for(integer i=0; i<`HNUM; i = i+1) begin
	for(integer j=0;j<`VNUM; j=j+1) begin
            if(i==0) begin 
                if(j==0) begin//(0,0)
                    //vlink
                    vlink_wdata_temp[i][j]=vlink_wdata[j];//todo 3_17 weight sharing query attention!!!
                    vlink_wen_temp[i][j]=vlink_wen[j];
                    //hlink
                    hlink_wdata_temp[i][j]=hlink_wdata[i];
                    hlink_wen_temp[i][j]=hlink_wen[i];
                end
		else if(j < `VNUM-1) begin//(0,1 to `VNUM-2)
                    //vlink
                    vlink_wdata_temp[i][j]=vlink_wdata[j];  
                    vlink_wen_temp[i][j]=vlink_wen[j];
                    //hlink
                    hlink_wdata_temp[i][j]=hlink_rdata_temp[i][j-1];
                    hlink_wen_temp[i][j]=hlink_rvalid_temp[i][j-1];
                end
                else begin//(0,`VNUM-1)
                    //vlink
                    vlink_wdata_temp[i][j]=vlink_wdata[j];
                    vlink_wen_temp[i][j]=vlink_wen[j];
                    //hlink
                    hlink_wdata_temp[i][j]=hlink_rdata_temp[i][j-1];
                    hlink_wen_temp[i][j]=hlink_rvalid_temp[i][j-1];
                    hlink_rdata[i]=hlink_rdata_temp[i][j];
                    hlink_rvalid[i]=hlink_rvalid_temp[i][j];
                end
            end
	else if(i < `VNUM-1) begin
                if(j==0) begin //(1 to `HNUM-2,0)
                    //vlink
                    vlink_wdata_temp[i][j]=vlink_rdata_temp[i-1][j];
                    vlink_wen_temp[i][j]=vlink_rvalid_temp[i-1][j];
                    //hlink
                    hlink_wdata_temp[i][j]=hlink_wdata[i];
                    hlink_wen_temp[i][j]=hlink_wen[i];
                end
	else if(j<`VNUM-1) begin //(1 to `HNUM-2,1 to `VNUM-2)
                    //vlink
                    vlink_wdata_temp[i][j]=vlink_rdata_temp[i-1][j];  
                    vlink_wen_temp[i][j]=vlink_rvalid_temp[i-1][j];
                    //hlink
                    hlink_wdata_temp[i][j]=hlink_rdata_temp[i][j-1];
                    hlink_wen_temp[i][j]=hlink_rvalid_temp[i][j-1];
                end
                else begin //(1 to `HNUM-2,`VNUM-1)
                    //vlink
                    vlink_wdata_temp[i][j]=vlink_rdata_temp[i-1][j];
                    vlink_wen_temp[i][j]=vlink_rvalid_temp[i-1][j];
                    //hlink
                    hlink_wdata_temp[i][j]=hlink_rdata_temp[i][j-1];
                    hlink_wen_temp[i][j]=hlink_rvalid_temp[i][j-1];
                    hlink_rdata[i]=hlink_rdata_temp[i][j];
                    hlink_rvalid[i]=hlink_rvalid_temp[i][j];
                end
            end
            else begin 
                if(j==0)begin //(`HNUM-1,0)
                    //vlink
                    vlink_wdata_temp[i][j]=vlink_rdata_temp[i-1][j];
                    vlink_wen_temp[i][j]=vlink_rvalid_temp[i-1][j];
                    vlink_rdata[j]=vlink_rdata_temp[i][j];
                    vlink_rvalid[j]=vlink_rvalid_temp[i][j];
                    //hlink
                    hlink_wdata_temp[i][j]=hlink_wdata[i];
                    hlink_wen_temp[i][j]=hlink_wen[i];
                end
	    else if(j<`VNUM-1) begin
                    //vlink
                    vlink_wdata_temp[i][j]=vlink_rdata_temp[i-1][j];  
                    vlink_wen_temp[i][j]=vlink_rvalid_temp[i-1][j];
                    vlink_rdata[j]=vlink_rdata_temp[i][j];
                    vlink_rvalid[j]=vlink_rvalid_temp[i][j];
                    //hlink
                    hlink_wdata_temp[i][j]=hlink_rdata_temp[i][j-1];
                    hlink_wen_temp[i][j]=hlink_rvalid_temp[i][j-1];
                end
                else begin
                    //vlink
                    vlink_wdata_temp[i][j]=vlink_rdata_temp[i-1][j];  
                    vlink_wen_temp[i][j]=vlink_rvalid_temp[i-1][j];
                    vlink_rdata[j]=vlink_rdata_temp[i][j];
                    vlink_rvalid[j]=vlink_rvalid_temp[i][j];
                    //hlink
                    hlink_wdata_temp[i][j]=hlink_rdata_temp[i][j-1];
                    hlink_wen_temp[i][j]=hlink_rvalid_temp[i][j-1];
                    hlink_rdata[i]=hlink_rdata_temp[i][j];
                    hlink_rvalid[i]=hlink_rvalid_temp[i][j];
                end
            end
        end
    end
end
//gbus wen gbus ren high at same time, `GBUS_ADDR
always @* begin: gbus_connection
	gbus_rdata={`HNUM*`VNUM*`GBUS_DATA{1'b0}};
//initialize
for(integer i=0;i< `HNUM; i = i+1) begin
	for(integer j=0;j< `VNUM; j=j+1) begin
            gbus_wdata_temp[i][j]= {`GBUS_DATA{1'b0}};
            GBUS_ADDR_temp[i][j]= {`GBUS_ADDR{1'b0}};
        end
    end
//gbus_rdata
for(integer i=0;i< `HNUM; i = i+1) begin
	for(integer j=0;j< `VNUM; j=j+1) begin
            if(gbus_rvalid[i][j]) begin
                gbus_rdata[i]=gbus_rdata_temp[i][j];
                break;
            end
        end
    end
    //gbus_wdata
    for(integer i=0;i< `HNUM; i = i+1) begin
        for(integer j=0;j< `VNUM; j=j+1) begin
            if(gbus_wen[i][j]) begin
                gbus_wdata_temp[i][j]=gbus_wdata[i];
                break;
            end
        end
    end
    //`GBUS_ADDR
    for(integer i=0;i< `HNUM; i = i+1) begin
        for(integer j=0;j< `VNUM; j=j+1) begin
            if(gbus_wen[i][j] | gbus_ren[i][j]) begin
                GBUS_ADDR_temp[i][j]=GBUS_ADDR[i];
                break;
            end
        end
    end
end

generate
    for (genvar i = 0; i < `HNUM; i = i+1)begin : gen_row
        for (genvar j = 0; j < `VNUM; j=j+1)begin : gen_col
            core_top core_top_instance (
                        .clk           (clk),
                        .rstn          (rstn),
                        .cfg_acc_num   (cfg_acc_num_reg[i][j]),
                        .cfg_quant_scale (arr_cfg_reg.cfg_quant_scale),
                        .cfg_quant_bias (arr_cfg_reg.cfg_quant_bias),
                        .cfg_quant_shift (arr_cfg_reg.cfg_quant_shift),
                        .GBUS_ADDR     (GBUS_ADDR_temp[i][j]), //gbus to weight mem, gbus to kv cache
                        .gbus_wen      (gbus_wen[i][j]),
                        .gbus_wdata    (gbus_wdata_temp[i][j]),
                        .gbus_ren      (gbus_ren[i][j]),
                        .gbus_rdata    (gbus_rdata_temp[i][j]),
                        .gbus_rvalid   (gbus_rvalid[i][j]),
                        .vlink_enable  (vlink_enable),
                        .vlink_wdata   (vlink_wdata_temp[i][j]), // access lbuf
                        .vlink_wen     (vlink_wen_temp[i][j]),
                        .vlink_rdata   (vlink_rdata_temp[i][j]),
                        .vlink_rvalid  (vlink_rvalid_temp[i][j]),
                        .hlink_wdata   (hlink_wdata_temp[i][j]), // access abuf
                        .hlink_wen     (hlink_wen_temp[i][j]),
                        .hlink_rdata   (hlink_rdata_temp[i][j]),
                        .hlink_rvalid  (hlink_rvalid_temp[i][j]),
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
