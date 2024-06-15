from os import path

from pyppa import PPARunner
from pyppa.tools.yosys import Yosys
from pyppa.tools.openroad import OpenROAD
from pyppa.tools.iverilog import Iverilog
from config import SKY130HD_PLATFORM_CONFIG

gcd_runner = PPARunner(
	design_name="vector_engine",
	tools={
		'verilog_sim_tool': Iverilog(scripts_dir=path.join('scripts', 'iverilog')),
		'synth_tool': Yosys(scripts_dir=path.join('scripts', 'synth')),
		'ppa_tool': OpenROAD(scripts_dir=path.join('scripts', 'ppa'))
	},
	platform_config=SKY130HD_PLATFORM_CONFIG,
	global_flow_config={
		'PLATFORM': 'sky130hd',
		'VERILOG_FILES': [
			path.join('..', 'HW', 'comp', 'vector_engine', 'softmax', 'rtl', 'softmax.v')
		],
		'DESIGN_DIR': path.join('..', 'HW', 'comp', 'vector_engine')
	},
	modules=[
		{
			'name': 'softmax',
			'mode': 'sweep',
			'flow_config': {
				'RUN_VERILOG_SIM': True,
				'VERILOG_SIM_TYPE': 'postsynth',
				'VERILOG_TESTBENCH_FILES': [path.join('..', 'HW', 'comp', 'vector_engine', 'softmax', 'tb', 'softmax_tb.v')],
				'USE_STA_VCD': True
			},
			'hyperparameters': {
				'clk_period': {
					'values': [10, 20, 30]
				}
			}
		}
	]
)

def sorter(x):
	return x[1]

gcd_runner.run_ppa_analysis()
gcd_runner.print_stats('ppa.txt')