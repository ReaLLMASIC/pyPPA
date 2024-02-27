#include <cstdlib>
#include <iostream>
#include <fstream>
#include <verilated.h>
#include <verilated_vcd_c.h>

#include "obj_dir/Vfinv.h"

#define UNIT_TIME       1
#define MAX_SIM_TIME    22*UNIT_TIME

int main(int argc, char** argv, char** env) {
    Vfinv *dut = new Vfinv;

    Verilated::traceEverOn(true);
    VerilatedVcdC *m_trace = new VerilatedVcdC;
    dut->trace(m_trace, 2);
    m_trace->open("finv.vcd");

    // srand(12);

    unsigned long mem;
    std::ifstream file_mem;
    file_mem.open("test.mem", std::ifstream::in);

    dut->clk        = 0;
    dut->rst        = 0;
    dut->ivalid     = 1;
    dut->idata      = 0;

    unsigned long sim_time = 0;
    while(sim_time < MAX_SIM_TIME){
        dut->clk ^= 1;
        if(dut->clk){
            file_mem >> std::hex >> mem;
            dut->idata = (mem >> 32);
        }
        dut->eval();
        m_trace->dump(sim_time);
        sim_time++;
    }

    dut->eval();
    m_trace->dump(sim_time);

    file_mem.close();
    m_trace->close();
    delete dut;
    dut = 0;
    exit(EXIT_SUCCESS);
}

