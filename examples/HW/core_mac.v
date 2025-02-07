`define MAC_NUM   = 8
`define MUL_ODATA_BIT = 16
`define ODATA_BIT = 16+$clog2(`MAC_NUM)
`define IDATA_BIT = 8
`define ADD_IDATA_BIT = 16
`define ADD_ODATA_BIT = 16 + $clog2(`MAC_NUM)
module core_mac (
    // Global Signals
    input                               clk,
    input                               rstn,

    // Data Signals
    input       [`IDATA_BIT*`MAC_NUM-1:0] idataA,
    input       [`IDATA_BIT*`MAC_NUM-1:0] idataB,
    input                               idata_valid,
    output      [`ODATA_BIT-1:0]         odata,
    output                              odata_valid
);
    // Multiplication
    wire    [`IDATA_BIT*2*`MAC_NUM-1:0]   product;
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
    adder_tree  #(.MAC_NUM(MAC_NUM), .IDATA_BIT(IDATA_BIT*2)) adt_inst (
        .clk                            (clk),
        .rstn                            (rstn),
        .idata                          (product),
        .idata_valid                    (product_valid),
        .odata                          (odata),
        .odata_valid                    (odata_valid)
    );  

endmodule

// =============================================================================
// MUL Line
// 1 cycle delay
module mul_line (
    // Global Signals
    input                               clk,
    input                               rstn,

    // Data Signals
    input       [`IDATA_BIT*`MAC_NUM-1:0] idataA,
    input       [`IDATA_BIT*`MAC_NUM-1:0] idataB,
    input                               idata_valid,
    output  reg [`MUL_ODATA_BIT*`MAC_NUM-1:0] odata,
    output  reg                         odata_valid
);

    // Input Gating
    reg     [`IDATA_BIT-1:0] idataA_reg  [0:`MAC_NUM-1];
    reg     [`IDATA_BIT-1:0] idataB_reg  [0:`MAC_NUM-1];

    genvar i;
    generate
        for (i = 0; i < `MAC_NUM; i = i + 1) begin: gen_mul_input
            always @(posedge clk or negedge rstn) begin
                if (!rstn) begin
                    idataA_reg[i] <= 'd0;
                    idataB_reg[i] <= 'd0;
                end
                else if (idata_valid) begin
                    idataA_reg[i] <= idataA[i*`IDATA_BIT+:`IDATA_BIT];
                    idataB_reg[i] <= idataB[i*`IDATA_BIT+:`IDATA_BIT];
                end
            end
        end
    endgenerate

    // Mutiplication
    wire    [`MUL_ODATA_BIT-1:0] product [0:`MAC_NUM-1];

    generate 
        for (i = 0; i < `MAC_NUM; i = i + 1) begin: gen_mul
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
        for (i = 0; i < `MAC_NUM; i = i + 1) begin: gen_mul_output
            always @(*) begin
                odata[i*`MUL_ODATA_BIT+:`MUL_ODATA_BIT] = product[i]; 
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

module mul_int (
    input       [`IDATA_BIT-1:0] idataA,
    input       [`IDATA_BIT-1:0] idataB,
    output      [`MUL_ODATA_BIT-1:0] odata    
);
    reg signed  [`MUL_ODATA_BIT-1:0] odata_comb;
    always @(*) begin
        odata_comb = $signed(idataA) * $signed(idataB);
    end
    assign  odata = odata_comb;
endmodule

// =============================================================================
// Configurable Adder Tree. Please double-check it's synthesizable.
// (STAGE_NUM+1)/2 delay
module adder_tree (
    // Global Signals
    input                               clk,
    input                               rstn,

    // Data Signals
    input       [`ADD_IDATA_BIT*`MAC_NUM-1:0] idata,
    input                               idata_valid,
    output  reg [`ADD_ODATA_BIT-1:0]         odata,
    output  reg                         odata_valid
);

    localparam  STAGE_NUM = $clog2(`MAC_NUM);

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
            localparam  OUT_BIT = `ADD_IDATA_BIT + (i + 1'b1);
            localparam  OUT_NUM = `MAC_NUM  >> (i + 1'b1);

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
                            add_idata[j*2]   <= idata[(j*2+0)*`ADD_IDATA_BIT+:`ADD_IDATA_BIT];
                            add_idata[j*2+1] <= idata[(j*2+1)*`ADD_IDATA_BIT+:`ADD_IDATA_BIT];
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
                add_int #(.IDATA_BIT(OUT_BIT-1), .ODATA_BIT(OUT_BIT)) adder_inst (
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
    parameter   IDATA_BIT = 8,
    parameter   ODATA_BIT = 9
)(
    // Data Signals
    input       [IDATA_BIT-1:0] idataA,
    input       [IDATA_BIT-1:0] idataB,
    output      [ODATA_BIT-1:0] odata
);

    reg signed  [ODATA_BIT-1:0] odata_comb;

    always @(*) begin
        odata_comb = $signed(idataA) + $signed(idataB);
    end

    assign  odata = odata_comb;

endmodule
