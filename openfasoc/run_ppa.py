from os import path

from pyppa import PPARunner
from pyppa.tools.yosys import Yosys
from pyppa.tools.openroad import OpenROAD
from pyppa.tools.iverilog import Iverilog
from platforms.sky130hd.config import SKY130HD_PLATFORM_CONFIG

gcd_runner = PPARunner(
	design_name="vector_engine",
	tools={
		'verilog_sim_tool': Iverilog(scripts_dir=path.join('scripts', 'iverilog')),
		'synth_tool': Yosys(scripts_dir=path.join('scripts', 'orfs')),
		'apr_tool': OpenROAD(scripts_dir=path.join('scripts', 'orfs'))
	},
	global_flow_config={
		**SKY130HD_PLATFORM_CONFIG,
		'PLATFORM': 'sky130hd',
		'VERILOG_FILES': [
			path.join('..', 'HW', 'comp', 'vector_engine', 'softmax', 'rtl', 'softmax.v'),
			path.join('..', 'HW', 'comp', 'vector_engine', 'softermax', 'rtl', 'softermax.v'),
			# path.join('..', 'HW', 'comp', 'vector_engine', 'consmax', 'rtl', 'consmax.v'),
		],
		'DESIGN_DIR': path.join('..', 'HW', 'comp', 'vector_engine'),
		'SCRIPTS_DIR': path.join('scripts', 'orfs'),
		'YOSYS_CMD': '/usr/bin/miniconda3/bin/yosys',
		'OPENROAD_CMD': '/usr/bin/miniconda3/bin/openroad',
		'KLAYOUT_CMD': 'klayout',
		'CORE_UTILIZATION': 40
	},
	modules=[
		{
			'name': 'softmax',
			'flow_config': {
				'RUN_PRESYNTH_SIM': True,
				'RUN_POSTSYNTH_SIM': False,
				'PRESYNTH_TESTBENCH': path.join('..', 'HW', 'comp', 'vector_engine', 'softmax', 'tb', 'softmax_tb.v'),
				'POSTSYNTH_TESTBENCH': path.join('..', 'HW', 'comp', 'vector_engine', 'softmax', 'tb', 'softmax_tb.v'),
				'USE_STA_VCD': True,
				'STA_VCD_TYPE': 'presynth'
			},
			'parameters': {}
		}
	]
)

def sorter(x):
	return x[1]

gcd_runner.run_ppa_analysis()
stats = sorted(gcd_runner.runs['softmax'][1]['synth_stats']['cell_counts'].items(), key=sorter, reverse=True)
print(stats)
gcd_runner.print_stats('ppa.txt')