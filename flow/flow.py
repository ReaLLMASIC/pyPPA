from os import path

from pyflow import PPARunner
from pyflow.tools.yosys import Yosys
from pyflow.tools.openroad import OpenROAD
from pyflow.tools.verilator import Verilator
from platforms.sky130hd.config import SKY130HD_PLATFORM_CONFIG

gcd_runner = PPARunner(
	design_name="vector_engine",
	tools={
		'verilog_sim_tool': Verilator(
			cmd='/usr/bin/miniconda3/bin/verilator',
			scripts_dir=path.join('scripts', 'verilator')
		),
		'synth_tool': Yosys(
			cmd='/usr/bin/miniconda3/bin/yosys',
			scripts_dir=path.join('scripts', 'orfs')
		),
		'apr_tool': OpenROAD(
			cmd='/usr/bin/miniconda3/bin/openroad',
			scripts_dir=path.join('scripts', 'orfs')
		)
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
		'UTILS_DIR': path.join('util', 'orfs'),
		'YOSYS_CMD': '/usr/bin/miniconda3/bin/yosys',
		'OPENROAD_CMD': '/usr/bin/miniconda3/bin/openroad',
		'KLAYOUT_CMD': 'klayout',
		'CORE_UTILIZATION': 40,
		'RUN_PRESYNTH_SIM': True,
		'PRESYNTH_TESTBENCH': path.join('test.cpp')
	},
	modules=[
		{
			'name': 'softmax',
			'flow_config': {},
			'parameters': {}
		},
		{
			'name': 'softermax',
			'flow_config': {},
			'parameters': {}
		}
	]
)

gcd_runner.run_ppa_analysis()
gcd_runner.print_stats('ppa.txt')