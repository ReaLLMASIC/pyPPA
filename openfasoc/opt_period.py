# This is a simple optimization example that obtains the best possible period for a design
# Given all the other parameters are constant (except the synth strategy)

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
	max_concurrent_jobs=2,
	threads_per_job=2,
	global_flow_config={
		'PLATFORM': 'sky130hd',
		'VERILOG_FILES': [
			path.join('..', 'HW', 'comp', 'vector_engine', 'softmax', 'rtl', 'softmax.v')
		],
		'DESIGN_DIR': path.join('..', 'HW', 'comp', 'vector_engine')
	}
)

INITIAL_PERIOD = 100
def period_optimizer(prev_iter_number, prev_iter_ppa_runs, constraint_period):
	# Use the minimum of the two strategies' periods
	next_period = min(
		prev_iter_ppa_runs[0]['ppa_stats']['sta']['clk']['clk_period'],
		prev_iter_ppa_runs[1]['ppa_stats']['sta']['clk']['clk_period']
	) if prev_iter_ppa_runs is not None else INITIAL_PERIOD

	if prev_iter_number != 0:
		# We want to reduce this objective as much as possible
		# The difference between the constraint period and the best period provided by STA
		# is reduced to 0. When it becomes 0, the actual best period is obtained
		# as the estimate provided by OpenSTA is more precise if the constraint period is close to the best period
		deviation = abs(constraint_period - next_period)
		print("Iteration:", prev_iter_number, "Deviation:", deviation, "Constraint period:", constraint_period, "Next period:", next_period)

		best_strategy = "ABC_SPEED" if prev_iter_ppa_runs[0]['ppa_stats']['sta']['clk']['clk_period'] < prev_iter_ppa_runs[1]['ppa_stats']['sta']['clk']['clk_period'] else "ABC_AREA"
		print(f"{best_strategy} had the lowest period. Difference: ", abs(prev_iter_ppa_runs[0]['ppa_stats']['sta']['clk']['clk_period'] - prev_iter_ppa_runs[1]['ppa_stats']['sta']['clk']['clk_period']))

		if deviation < 1e-10:
			# If the deviation becomes small enough, stop optimizing
			print("Optimization complete. Best period:", next_period,  "Devation:", deviation, "Best strategy:", best_strategy)
			return {
				'opt_complete': True
			}
		elif prev_iter_number > 15:
			print("More than 15 iterations later, the deviation is still too big. Stopping optimization. Best period:", next_period, "Constraint period:", constraint_period, "Deviation:", deviation)
			return {
				'opt_complete': True
			}

	return {
		'opt_complete': False,
		'next_suggestions': [
			# Suggest both ABC_AREA: True and False
			{
				'flow_config': {
					'ABC_AREA': False
				},
				'hyperparameters': {
					'clk_period': next_period
				}
			},
			{
				'flow_config': {
					'ABC_AREA': True
				},
				'hyperparameters': {
					'clk_period': next_period
				}
			}
		],
		'context': next_period
	}

gcd_runner.add_job({
	'module_name': 'softmax',
	'mode': 'opt',
	'optimizer': period_optimizer
})

gcd_runner.run_all_jobs()