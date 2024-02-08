from os import path

from pyflow import PPARunner
from platforms.sky130hd.config import SKY130HD_PLATFORM_CONFIG

gcd_runner = PPARunner(
	design_name="vector_engine",
	global_flow_config={
		**SKY130HD_PLATFORM_CONFIG,
		'PLATFORM': 'sky130hd',
		'VERILOG_FILES': [
			path.join('..', 'HW', 'comp', 'vector_engine', 'softmax', 'rtl', 'softmax.v'),
			path.join('..', 'HW', 'comp', 'vector_engine', 'softermax', 'rtl', 'softermax.v')
		],
		'DESIGN_DIR': path.join('..', 'HW', 'comp', 'vector_engine'),
		'SCRIPTS_DIR': path.join('scripts', 'orfs'),
		'UTILS_DIR': path.join('util', 'orfs'),
		'YOSYS_CMD': '/usr/bin/miniconda3/bin/yosys',
		'OPENROAD_CMD': '/usr/bin/miniconda3/bin/openroad',
		'KLAYOUT_CMD': 'klayout',
		'CORE_UTILIZATION': 40
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
gcd_runner.print_stats()