`define IDATA_BIT = (16+$clog2(8))
`define ODATA_BIT = 16
`define CDATA_BIT = 8

module core_acc (
    // Global Signals
    input                       clk,
    input                       rstn,

    // Global Config Signals
    input       [`CDATA_BIT-1:0] cfg_acc_num,

    // Data Signals
    input       [`IDATA_BIT-1:0] idata,
    input                       idata_valid,
    output      [`ODATA_BIT-1:0] odata,
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

// =============================================================================
// FSM for Accumulation Counter

module core_acc_ctrl (
    // Global Signals
    input                       clk,
    input                       rstn,

    // Config Signals
    input       [`CDATA_BIT-1:0] cfg_acc_num,

    // Control Signals
    input                       psum_valid,
    output  reg                 psum_finish
);

    parameter   PSUM_IDLE   = 2'b01,
                PSUM_UPDATE = 2'b10;
    reg [1:0]   psum_state;

    reg     [`CDATA_BIT-1:0] psum_cnt;
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

// =============================================================================
// Computing Logic in Accumulation

module core_acc_mac (
    // Global Signals
    input                       clk,
    input                       rstn,

    // Control Signals
    input                       pre_finish,

    // Data Signals
    input       [`IDATA_BIT-1:0] idata,
    input                       idata_valid,
    output  reg [`ODATA_BIT-1:0] odata,
    output  reg                 odata_valid
);

    // Input Gating
    reg signed  [`IDATA_BIT-1:0] idata_reg;
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
    reg signed  [`ODATA_BIT-1:0] acc_reg;

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
