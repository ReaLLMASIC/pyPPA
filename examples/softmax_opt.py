# This is a more complex and useful optimization example that uses the Vizier optimization tool by Google for running the optimization. See https://github.com/google/vizier for more information on Vizier.
# Install vizier using `pip install google-vizier[jax]`

from vizier import service
from vizier.service import clients
from vizier.service import pyvizier as vz

import sys
from os import path

sys.path.append(path.join(path.dirname(__file__), '..'))

from pyppa import PPARunner
from pyppa.tools import Yosys, OpenROAD, Iverilog
from pyppa.ppa.ppa_runner import PPARunner
from platforms.sky130hd.config import SKY130HD_PLATFORM_CONFIG


ppa_runner = PPARunner(
	design_name="softmax",
	tools={
		'verilog_sim_tool': Iverilog(scripts_dir=path.join('scripts', 'iverilog')),
		'synth_tool': Yosys(scripts_dir=path.join('scripts', 'synth')),
		'ppa_tool': OpenROAD(scripts_dir=path.join('scripts', 'ppa'))
	},
	platform_config=SKY130HD_PLATFORM_CONFIG,
	threads_per_job=3,
	global_flow_config={
		'VERILOG_FILES': [
			path.join(path.dirname(__file__), 'HW', 'softmax.v')
		],
		'SDC_FILE': path.join(path.dirname(__file__), 'HW', 'constraint.sdc')
	}
)

problem = vz.ProblemStatement()
problem.search_space.root.add_float_param(name='constraint_period', min_value=8, max_value=15, default_value=15) # Guessing that the optimal period is somewhere in between, based on previous results
# problem.search_space.root.add_bool_param('abc_area')
problem.search_space.root.add_int_param(name='ABC_MAX_FANOUT', min_value=12, max_value=28, default_value=20) # Guessing the ABC max fanout is somewhere between 12 and 28
problem.search_space.root.add_float_param(name='ABC_MAP_EFFORT', min_value=0, max_value=1, default_value=0.6) # Guessing the ABC map effort is somewhere between 0 and 1
problem.search_space.root.add_discrete_param(name='num_softmax', feasible_values=[4,8,16,32], default_value=8) # Number of softmax buffers
problem.metric_information.append(
    vz.MetricInformation(
        name='fom',
		goal=vz.ObjectiveMetricGoal.MINIMIZE
	)
)

study_config = vz.StudyConfig.from_problem(problem)
study_config.algorithm = 'DEFAULT'
study_client = clients.Study.from_study_config(
  study_config,
  owner='ppa_runner',
  study_id='ppa_softmax_optimizer'
)
print('Local SQL database file located at: ', service.VIZIER_DB_PATH)

def fom(area: float, period: float, total_power: float, num_softmax: int):
    w1 = 0.6
    w2 = 0.2
    w3 = 0.2
    target_power = 10
    target_area = 2000
    target_throughput = 1e7
	
    throughput = 1e9 / period / num_softmax

    out = w1 * (area / target_area) + w2 * (total_power / target_power) - w3 * (throughput / target_throughput)

	# The objective function/figure of merit (which is minimized), is the product of the area, period, and power attempts to minimize all three.
    return out

def vizier_optimizer(prev_iter_number, prev_iter_ppa_runs: list[PPARunner], previous_suggestions):
	if prev_iter_ppa_runs is not None:
		if len(prev_iter_ppa_runs) != len(previous_suggestions):
			print("Number of runs does not match number of suggestions. Something went wrong, aborting.")
			return {
				'opt_complete': True
			}

		for i, suggestion in enumerate(previous_suggestions):
			constraint_period = suggestion.parameters['constraint_period']
			abc_max_fanout = suggestion.parameters['ABC_MAX_FANOUT']
			abc_map_effort = suggestion.parameters['ABC_MAP_EFFORT']
			num_softmax = suggestion.parameters['num_softmax']

			run = prev_iter_ppa_runs[i]
			area = run['synth_stats']['module_area']
			period = run['ppa_stats']['sta']['clk']['clk_period']
			total_power = run['ppa_stats']['power_report']['total']['total_power']
			throughput = 1e9 / period / num_softmax
    
			objective = fom(
				area=area,
				period=period,
				total_power=total_power,
				num_softmax=num_softmax
			)

			print(f'Iteration {prev_iter_number}, suggestion (constraint_period = {constraint_period}, abc_max_fanout = {abc_max_fanout}, abc_map_effort = {abc_map_effort}) led to\n')
			print(f'area {area} period {period} total_power {total_power} throughput {throughput} objective value {objective}.')
			final_measurement = vz.Measurement({'fom': objective})
			suggestion.complete(final_measurement)

	if prev_iter_number >= 20: # Run for 10 iterations and then stop
		print("Optimization complete.")
		# Print the optimal Vizier trials
		for optimal_trial in study_client.optimal_trials():
			optimal_trial = optimal_trial.materialize()
			print(
				"Optimal Trial Suggestion and Objective:",
				optimal_trial.parameters,
				optimal_trial.final_measurement
			)

		return {
			'opt_complete': True
		}

	# Assign new suggestions
	suggestions = study_client.suggest(count=3) # Since 3 threads per job
	print(suggestions[0].parameters)
	return {
		'opt_complete': False,
		'next_suggestions': [
			{
				'flow_config': {
					'ABC_MAX_FANOUT': suggestion.parameters['ABC_MAX_FANOUT'],
					'ABC_MAP_EFFORT': suggestion.parameters['ABC_MAP_EFFORT']
				},
				'hyperparameters': {
					'clk_period': suggestion.parameters['constraint_period'],
					'num_softmax': suggestion.parameters['num_softmax']
				}
			} for suggestion in suggestions
		],
		'context': suggestions # Send suggestions as context, and they will be sent as arguments for the next run of the optimizer.
	}

ppa_runner.add_job({
	'module_name': 'softmax',
	'mode': 'opt',
	'optimizer': vizier_optimizer
})

ppa_runner.run_all_jobs() 