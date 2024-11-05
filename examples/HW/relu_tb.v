`timescale 1ns/1ps

module relu_tb;

    // Parameters
    parameter integer sig_width = 7;
    parameter integer exp_width = 8;
    parameter integer BUS_NUM = 8;
    parameter integer BUS_NUM_WIDTH = 3;
    parameter integer DATA_NUM_WIDTH = 10;
    parameter integer SCALA_POS_WIDTH = 5;
    parameter integer FIXED_DATA_WIDTH = 8;
    parameter integer MEM_WIDTH = (BUS_NUM * FIXED_DATA_WIDTH);
    parameter integer MEM_DEPTH = 512;

    // Signals
    reg clk;
    reg rst_n;
    reg signed [BUS_NUM * FIXED_DATA_WIDTH - 1 : 0] in_fixed_data;
    reg [BUS_NUM-1:0] in_fixed_data_vld;
    wire signed [BUS_NUM * FIXED_DATA_WIDTH - 1 : 0] out_fixed_data;
    wire [BUS_NUM-1:0] out_fixed_data_vld;

    // Instantiate the ReLU module
    relu uut (
        .clk(clk),
        .rst_n(rst_n),
        .in_fixed_data(in_fixed_data),
        .in_fixed_data_vld(in_fixed_data_vld),
        .out_fixed_data(out_fixed_data),
        .out_fixed_data_vld(out_fixed_data_vld)
    );

    // Clock generation
    always #${clk_period / 2} clk = ~clk;

    // Test sequence
    initial begin
        // Initialize inputs
        $dumpfile("relu.vcd");
        $dumpvars(0, relu_tb);
        rst_n = 0;
        in_fixed_data = 0;
        in_fixed_data_vld = 0;

        // Apply reset
        #10 rst_n = 1;

        // Test case 1: All positive inputs
        #10;
        in_fixed_data = {8'h80, 8'd20, 8'd30, 8'd40, 8'd50, 8'd60, 8'd70, 8'hff};
        in_fixed_data_vld = 8'b11111111;
        #10;

        // Test case 5: All zero input data
        in_fixed_data = {8{8'd0}};
        in_fixed_data_vld = 8'b11111111;
        #10;

        // End simulation
        #20;
        $finish;
    end


endmodule
