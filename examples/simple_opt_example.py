from os import path
import sys

sys.path.append('..')

from pyppa import PPARunner
from pyppa.tools.yosys import Yosys
from pyppa.tools.openroad import OpenROAD
from pyppa.tools.iverilog import Iverilog
from platforms.sky130hd.config import SKY130HD_PLATFORM_CONFIG

def example_optimizer(prev_iter_number, prev_iter_ppa_runs):
	if prev_iter_ppa_runs is not None:
		for run in prev_iter_ppa_runs:
			if run['synth_stats']['num_cells'] < 30_000:
				return {
					'opt_complete': True
				}

	if prev_iter_number >= 2:
		print("Optimization could not converge. Stopping optimization.")
		return {
			'opt_complete': True
		}

	return {
		'opt_complete': False,
		'next_suggestions': [
			# Suggest both ABC_AREA: True and False
			{
				'flow_config': {
					'ABC_AREA': True
				},
				'hyperparameters': {
					'clk_period': 10
				}
			},
			{
				'flow_config': {
					'ABC_AREA': False
				},
				'hyperparameters': {
					'clk_period': 10
				}
			}
		]
	}

ppa_runner = PPARunner(
	design_name="softmax",
	tools={
		'verilog_sim_tool': Iverilog(scripts_dir=path.join('scripts', 'iverilog')),
		'synth_tool': Yosys(scripts_dir=path.join('scripts', 'synth')),
		'ppa_tool': OpenROAD(scripts_dir=path.join('scripts', 'ppa'))
	},
	platform_config=SKY130HD_PLATFORM_CONFIG,
	max_concurrent_jobs=2,
	threads_per_job=2,
	global_flow_config={
		'VERILOG_FILES': [
			path.join(path.dirname(__file__), 'HW', 'softmax.v')
		],
		'DESIGN_DIR': path.join(path.dirname(__file__), 'HW')
	}
)

ppa_runner.add_job({
	'module_name': 'softmax',
	'mode': 'opt',
	'optimizer': example_optimizer
})

ppa_runner.run_all_jobs()