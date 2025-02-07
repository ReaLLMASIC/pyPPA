`define IDATA_BIT = 16
`define ODATA_BIT = 8
module core_quant (
    // Global Signals
    input                       clk,
    input                       rstn,

    // Global Config Signals
    input       [`IDATA_BIT-1:0] cfg_quant_scale,
    input       [`IDATA_BIT-1:0] cfg_quant_bias,
    input       [`IDATA_BIT-1:0] cfg_quant_shift,

    // Data Signals
    input       [`IDATA_BIT-1:0] idata,
    input                       idata_valid,
    output  reg [`ODATA_BIT-1:0] odata,
    output  reg                 odata_valid
);

    // Input Gating
    // Causing the input from the accumulator register, no pipeline needed here

    // Quantize: Scale x Input + Bias
    reg signed  [`IDATA_BIT*2-1:0]   quantized_product,quantized_bias;
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
    reg signed  [`IDATA_BIT*2-1:0]   quantized_shift,quantized_shift_reg;
    reg signed  [`IDATA_BIT*2-1:0]   quantized_round,quantized_round_reg;

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
        quantized_round = $signed(quantized_shift_reg[`IDATA_BIT*2-1:1]) + 
        $signed({quantized_shift_reg[`IDATA_BIT*2-1], quantized_shift_reg[0]});
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
    reg         [ODATA_BIT-1:0]     quantized_overflow;

    always @(*) begin
        if ((quantized_round_reg[`IDATA_BIT*2-1] ^ (&quantized_round_reg[`IDATA_BIT*2-2:`ODATA_BIT-1])) ||
            (quantized_round_reg[`IDATA_BIT*2-1] ^ (|quantized_round_reg[`IDATA_BIT*2-2:`ODATA_BIT-1]))) begin
            quantized_overflow = {quantized_round_reg[`IDATA_BIT*2-1], 
                                  {(`ODATA_BIT-1){~quantized_round_reg[`IDATA_BIT*2-1]}}};
        end
        else begin
            quantized_overflow = {quantized_round_reg[`IDATA_BIT*2-1], quantized_round_reg[`ODATA_BIT-2:0]};
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
