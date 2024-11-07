// Copyright (c) 2024, Saligane's Group at University of Michigan and Google Research
//
// Licensed under the Apache License, Version 2.0 (the "License");

// you may not use this file except in compliance with the License.

// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// =============================================================================
// ConSmax Top Module
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
    input       [IDATA_BIT-1:0] idata,
    input                       idata_valid,
    output  reg [ODATA_BIT-1:0] odata,
    output  reg                 odata_valid
);

    // Clock Gating for Input
    reg     [IDATA_BIT-1:0] idata_reg;
    reg                     idata_valid_reg;

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

    // LUT Initialization: Convert INT to FP
    wire    [LUT_ADDR-1:0]  lut_addr    [0:1];
    wire    [LUT_DATA-1:0]  lut_rdata   [0:1];
    wire                    lut_ren;
    reg                     lut_rvalid;

    assign  lut_addr[0] = lut_wen && ~lut_waddr[LUT_ADDR] ? lut_waddr[LUT_ADDR-1:0] :
                                                            idata_reg[LUT_ADDR-1:0];
    assign  lut_addr[1] = lut_wen &&  lut_waddr[LUT_ADDR] ? lut_waddr[LUT_ADDR-1:0] :
                                                            idata_reg[LUT_ADDR+:LUT_ADDR];
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

    // mul_fp #(.EXP_BIT(EXP_BIT), .MAT_BIT(MAT_BIT), .DATA_BIT(LUT_DATA)) fpmul_inst (
    //     .idataA                 (lut_rdata[0]),
    //     .idataB                 (lut_rdata[1]),
    //     .odata                  (lut_product)
    // );

    // use fpmult for fixed data format
    fpmult fpmul_inst (
        .fout(lut_product),
        .f1(lut_rdata[0]),
        .f2(lut_rdata[1])
    );

    // Convert FP to INT
    wire    [ODATA_BIT-1:0] odata_comb;

    fp2int  #(.EXP_BIT(EXP_BIT), .MAT_BIT(MAT_BIT), .ODATA_BIT(ODATA_BIT), .CDATA_BIT(CDATA_BIT)) fp2int_inst (
        .cfg_consmax_shift      (cfg_consmax_shift),
        .idata                  (lut_product),
        .odata                  (odata_comb)
    );

    // Output
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            odata <= 'd0;
        end
        else if (lut_rvalid) begin
            odata <= odata_comb;
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

// =============================================================================
// Floating-Point Multiplier

//////////////////////////////////////////////////////////
// floating point multiply 
// -- sign bit -- 8-bit exponent -- 9-bit mantissa
// Similar to fp_mult from altera
// NO denorms, no flags, no NAN, no infinity, no rounding!
//////////////////////////////////////////////////////////
// f1 = {s1, e1, m1), f2 = {s2, e2, m2)
// If either is zero (zero MSB of mantissa) then output is zero
// If e1+e2<129 the result is zero (underflow)
///////////////////////////////////////////////////////////	
module fpmult (fout, f1, f2);

	input [17:0] f1, f2 ;
	output [17:0] fout ;
	
	wire [17:0] fout ;
	reg sout ;
	reg [8:0] mout ;
	reg [8:0] eout ; // 9-bits for overflow
	
	wire s1, s2;
	wire [8:0] m1, m2 ;
	wire [8:0] e1, e2, sum_e1_e2 ; // extend to 9 bits to avoid overflow
	wire [17:0] mult_out ;	// raw multiplier output
	
	// parse f1
	assign s1 = f1[17]; 	// sign
	assign e1 = {1'b0, f1[16:9]};	// exponent
	assign m1 = f1[8:0] ;	// mantissa
	// parse f2
	assign s2 = f2[17];
	assign e2 = {1'b0, f2[16:9]};
	assign m2 = f2[8:0] ;
	
	// first step in mult is to add extended exponents
	assign sum_e1_e2 = e1 + e2 ;
	
	// build output
	// raw integer multiply
	// unsigned_mult mm(mult_out, m1, m2);
	assign mult_out=m1*m2;
	 
	// assemble output bits
	assign fout = {sout, eout[7:0], mout} ;
	
	always @(*)
	begin
		// if either is denormed or exponents are too small
		if ((m1[8]==1'd0) || (m2[8]==1'd0) || (sum_e1_e2 < 9'h82)) 
		begin 
			mout = 0;
			eout = 0;
			sout = 0; // output sign
		end
		else // both inputs are nonzero and no exponent underflow
		begin
			sout = s1 ^ s2 ; // output sign
			if (mult_out[17]==1)
			begin // MSB of product==1 implies normalized -- result >=0.5
				eout = sum_e1_e2 - 9'h80;
				mout = mult_out[17:9] ;
			end
			else // MSB of product==0 implies result <0.5, so shift ome left
			begin
				eout = sum_e1_e2 - 9'h81;
				mout = mult_out[16:8] ;
			end	
		end // nonzero mult logic
	end // always @(*)
	
endmodule
