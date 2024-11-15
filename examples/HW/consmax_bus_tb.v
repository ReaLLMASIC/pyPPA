`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2024/11/14 23:46:09
// Design Name: 
// Module Name: consmax_bus_tb
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module consmax_bus_tb;

  // Parameters
  localparam IDATA_BIT = 8;
  localparam ODATA_BIT = 8;
  localparam CDATA_BIT = 8;
  localparam EXP_BIT = 8;
  localparam MAT_BIT = 7;
  localparam LUT_DATA = EXP_BIT + MAT_BIT + 1;
  localparam LUT_ADDR = IDATA_BIT >> 1;
  localparam LUT_DEPTH = 2 ** LUT_ADDR;
  
  parameter GBUS_DATA = 32;
  parameter GBUS_WIDTH = 4;
  parameter NUM_HEAD = 4;

  // Signals
  reg clk, rstn;
  reg [CDATA_BIT-1:0] cfg_consmax_shift;
  reg [LUT_ADDR:0] lut_waddr;
  reg lut_wen;
  reg [LUT_DATA-1:0] lut_wdata;
  reg [(GBUS_DATA*NUM_HEAD)-1:0] idata;
  reg [NUM_HEAD-1:0] idata_valid;
  wire [(GBUS_DATA*NUM_HEAD)-1:0] odata;
  wire [(GBUS_WIDTH*NUM_HEAD)-1:0] odata_valid;

  //random floating point gen
  reg  rand_sign;
  reg  [EXP_BIT-1:0] rand_exp;
  reg  [MAT_BIT-1:0] rand_man;

  // Instantiate the DUT
  consmax_bus dut (
    .clk(clk),
    .rstn(rstn),
    .cfg_consmax_shift(cfg_consmax_shift),
    .lut_waddr(lut_waddr),
    .lut_wen(lut_wen),
    .lut_wdata(lut_wdata),
    .idata(idata),
    .idata_valid(idata_valid),
    .odata(odata),
    .odata_valid(odata_valid)
  );

  // Clock generation
always #${clk_period / 2} clk = ~clk;
//   always #10 clk = ~clk;


  // Testbench logic
  initial begin
    // Initialize signals
    $dumpfile("consmax_bus.vcd");
    $dumpvars(0, consmax_bus_tb);

    clk = 0;
    rstn = 0;
    cfg_consmax_shift = 0;
    lut_waddr = 0;
    lut_wen = 0;
    lut_wdata = 0;
    idata = 0;
    idata_valid = 0;

    @(negedge clk);
    @(negedge clk);
    rstn = 1;

    write_lut();

    repeat (500) begin
      input_gen();
    end


    // Finish simulation
    #100 $finish;
  end

  integer i, j;
  task write_lut;
  begin
        lut_wen=1;
        for(i=0;i<=LUT_DEPTH*2;i = i + 1) begin
            @(negedge clk)
            lut_waddr=i;
            rand_sign=$random%2;
            rand_exp=$random%(2**EXP_BIT);
            rand_man=$random%(2**MAT_BIT);
            lut_wdata={rand_sign,rand_exp,rand_man};
        end
        lut_wen=0;
  end
  endtask

    task input_gen;
    begin
        @(posedge clk)
        cfg_consmax_shift=$random;
        for (i = 0; i < NUM_HEAD; i = i + 1) begin 
            for (j = 0; j < GBUS_WIDTH; j = j + 1) begin
                rand_sign=$random%2;
                rand_exp=$random%(2**EXP_BIT);
                rand_man=$random%(2**MAT_BIT);
                idata[i*GBUS_DATA+j*IDATA_BIT+:IDATA_BIT]={rand_sign,rand_exp,rand_man};
            end
            idata_valid[i]=1;
        end
    end
    endtask

endmodule
