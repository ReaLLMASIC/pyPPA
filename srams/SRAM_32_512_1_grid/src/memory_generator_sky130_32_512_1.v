`define USE_POWER_PINS
module memory_generator_sky130 #(parameter ALL_MEM_DATA_WIDTH = 32, parameter ALL_MEM_NUM_ADDRESSES = 512, parameter MEM_TYPE = 1 /*0 = 8x1024, 1 = 32x256, 2 = 32x512 */)(
// Port0 signals
	`ifdef USE_POWER_PINS
	   inout vccd1,
	   inout vssd1,
	`endif
	input clk0,
	input csb0,
	input web0,
	input [(ALL_MEM_DATA_WIDTH/8)-1:0] wmask0,
	input [$clog2(ALL_MEM_NUM_ADDRESSES)-1:0] port0_address,
	input [ALL_MEM_DATA_WIDTH-1:0] port0_datain,
	output[ALL_MEM_DATA_WIDTH-1:0] port0_dataout,

// Port1 signals
	input clk1,
	input csb1,
	input [$clog2(ALL_MEM_NUM_ADDRESSES)-1:0] port1_address,
	output [ALL_MEM_DATA_WIDTH-1:0] port1_dataout
);

// Local Parameters //
localparam SINGLE_MEM_DATA_WIDTH = MEM_TYPE == 0 ? 8 : 32;
localparam SINGLE_MEM_NUM_ADDRESSES = MEM_TYPE == 0 ? 1024 : (MEM_TYPE == 1 ? 256 : 512) ;
localparam ALL_MEM_ADDRESS_BITS = $clog2(ALL_MEM_NUM_ADDRESSES);
localparam SINGLE_MEM_ADDRESS_BITS = $clog2(SINGLE_MEM_NUM_ADDRESSES);
localparam NUM_SERIAL_MEMORIES = (ALL_MEM_NUM_ADDRESSES) / (SINGLE_MEM_NUM_ADDRESSES);
localparam NUM_PARALLEL_MEMORIES = (ALL_MEM_DATA_WIDTH) / (SINGLE_MEM_DATA_WIDTH);
localparam NUM_BITS_SELECT_MEMORIES = $clog2(NUM_SERIAL_MEMORIES);

// Local Variables //
wire [NUM_SERIAL_MEMORIES - 1:0] bus_we;
wire [ALL_MEM_DATA_WIDTH*NUM_SERIAL_MEMORIES - 1:0] port0_bus_odata;
wire [ALL_MEM_DATA_WIDTH*NUM_SERIAL_MEMORIES - 1:0] port1_bus_odata;
reg [31:0] port0_addr0_reg, port0_addr0_reg1;
reg [31:0] port1_addr1_reg, port1_addr1_reg1;

initial begin
	if(SINGLE_MEM_DATA_WIDTH > ALL_MEM_DATA_WIDTH || SINGLE_MEM_NUM_ADDRESSES > ALL_MEM_NUM_ADDRESSES)
		$fatal("INVALID PARAMETERS");
end

genvar i,j;
generate 

	for (i=0; i < NUM_SERIAL_MEMORIES; i=i+1) begin: SERIAL_MEMORY
		for(j=0; j < NUM_PARALLEL_MEMORIES; j=j+1) begin: PARALLEL_MEMORY
			if(SINGLE_MEM_DATA_WIDTH == 32 && SINGLE_MEM_NUM_ADDRESSES == 512) begin // 32x512 memory type
				sky130_sram_2kbyte_1rw1r_32x512_8 sky130_sram_2kbyte_1rw1r_32x512_8_i (
					`ifdef USE_POWER_PINS
					    vccd1,
					    vssd1,
					`endif 
					 clk0,
					 csb0,
					 bus_we[i],
					 wmask0[((j+1)*4)-1:j*4],
					 port0_address[ALL_MEM_ADDRESS_BITS-1:NUM_BITS_SELECT_MEMORIES],
					 port0_datain[(j+1)*SINGLE_MEM_DATA_WIDTH - 1:j*SINGLE_MEM_DATA_WIDTH],
					 port0_bus_odata[ ( ((j+1)*SINGLE_MEM_DATA_WIDTH) + (i*ALL_MEM_DATA_WIDTH) ) - 1 : (j*SINGLE_MEM_DATA_WIDTH)  + (i*ALL_MEM_DATA_WIDTH)],
					 clk1,
					 csb1,
					 port1_address[ALL_MEM_ADDRESS_BITS-1:NUM_BITS_SELECT_MEMORIES],
					 port1_bus_odata[ ( ((j+1)*SINGLE_MEM_DATA_WIDTH) + (i*ALL_MEM_DATA_WIDTH) ) - 1 : (j*SINGLE_MEM_DATA_WIDTH)  + (i*ALL_MEM_DATA_WIDTH)]
				);
			end else if(SINGLE_MEM_DATA_WIDTH == 32 && SINGLE_MEM_NUM_ADDRESSES == 256) begin // 32x256 memory type
				sky130_sram_1kbyte_1rw1r_32x256_8 sky130_sram_1kbyte_1rw1r_32x256_8_i (
					`ifdef USE_POWER_PINS
					    vccd1,
					    vssd1,
					`endif 
					 clk0,
					 csb0,
					 bus_we[i],
					 wmask0[((j+1)*4)-1:j*4],
					 port0_address[ALL_MEM_ADDRESS_BITS-1:NUM_BITS_SELECT_MEMORIES],
					 port0_datain[(j+1)*SINGLE_MEM_DATA_WIDTH - 1:j*SINGLE_MEM_DATA_WIDTH],
					 port0_bus_odata[ ( ((j+1)*SINGLE_MEM_DATA_WIDTH) + (i*ALL_MEM_DATA_WIDTH) ) - 1 : (j*SINGLE_MEM_DATA_WIDTH)  + (i*ALL_MEM_DATA_WIDTH)],
					 clk1,
					 csb1,
					 port1_address[ALL_MEM_ADDRESS_BITS-1:NUM_BITS_SELECT_MEMORIES],
					 port1_bus_odata[ ( ((j+1)*SINGLE_MEM_DATA_WIDTH) + (i*ALL_MEM_DATA_WIDTH) ) - 1 : (j*SINGLE_MEM_DATA_WIDTH)  + (i*ALL_MEM_DATA_WIDTH)]
				);
			end else begin // 8x1024 memory type
				sky130_sram_1kbyte_1rw1r_8x1024_8 sky130_sram_1kbyte_1rw1r_8x1024_8_i (
					`ifdef USE_POWER_PINS
					    vccd1,
					    vssd1,
					`endif 
					 clk0,
					 csb0,
					 bus_we[i],
					 {1'b0,wmask0[((j+1))-1:j]}, //wmask0 must be generated as wmask0[0] in the netlist, to do that wmask0 uses 2 bits, to avoid synth errors on OpenLAne the MSB is conected to GND
					 port0_address[ALL_MEM_ADDRESS_BITS-1:NUM_BITS_SELECT_MEMORIES],
					 port0_datain[(j+1)*SINGLE_MEM_DATA_WIDTH - 1:j*SINGLE_MEM_DATA_WIDTH],
					 port0_bus_odata[ ( ((j+1)*SINGLE_MEM_DATA_WIDTH) + (i*ALL_MEM_DATA_WIDTH) ) - 1 : (j*SINGLE_MEM_DATA_WIDTH)  + (i*ALL_MEM_DATA_WIDTH)],
					 clk1,
					 csb1,
					 port1_address[ALL_MEM_ADDRESS_BITS-1:NUM_BITS_SELECT_MEMORIES],
					 port1_bus_odata[ ( ((j+1)*SINGLE_MEM_DATA_WIDTH) + (i*ALL_MEM_DATA_WIDTH) ) - 1 : (j*SINGLE_MEM_DATA_WIDTH)  + (i*ALL_MEM_DATA_WIDTH)]
				);
			end
		end
    end

		if (NUM_SERIAL_MEMORIES > 1) begin
		
			for(i = 0 ; i < NUM_SERIAL_MEMORIES; i=i+1) begin : WE_ASSIGN
				assign bus_we[i] = ~((~web0) && (i == port0_address[NUM_BITS_SELECT_MEMORIES-1:0]));
			end
			assign port1_dataout = port1_bus_odata>>(port1_addr1_reg1*ALL_MEM_DATA_WIDTH);
			assign port0_dataout = port0_bus_odata>>(port0_addr0_reg1*ALL_MEM_DATA_WIDTH);
			
		end else begin
		
			assign bus_we = (web0);
			assign port1_dataout = port1_bus_odata;
			assign port0_dataout = port0_bus_odata;
			
		end
		
endgenerate

  // All inputs are registers
  always @(posedge clk0) begin
		port0_addr0_reg <= port0_address[NUM_BITS_SELECT_MEMORIES-1:0];
		port0_addr0_reg1 <= port0_addr0_reg;
  end

  always @(posedge clk1) begin
		port1_addr1_reg <= port1_address[NUM_BITS_SELECT_MEMORIES-1:0];
		port1_addr1_reg1 <= port1_addr1_reg;
  end

endmodule
