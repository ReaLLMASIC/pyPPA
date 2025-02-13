# This is a more complex and useful optimization example that uses the Vizier optimization tool by Google for running the optimization. See https://github.com/google/vizier for more information on Vizier.
# Install vizier using `pip install google-vizier[jax]`

from vizier import service
from vizier.service import clients
from vizier.service import pyvizier as vz
import numpy as np

import sys
from os import path

sys.path.append(path.join(path.dirname(__file__), '..'))

from pyppa import PPARunner
from pyppa.tools import Yosys, OpenROAD, Iverilog
from pyppa.ppa.ppa_runner import PPARunner
from platforms.sky130hd.config import SKY130HD_PLATFORM_CONFIG

import math

ppa_runner = PPARunner(
	design_name="core_array",
	tools={
		'verilog_sim_tool': Iverilog(scripts_dir=path.join('scripts', 'iverilog')),
		'synth_tool': Yosys(scripts_dir=path.join('scripts', 'synth')),
		'ppa_tool': OpenROAD(scripts_dir=path.join('scripts', 'ppa'))
	},
	platform_config=SKY130HD_PLATFORM_CONFIG,
	threads_per_job=3,
	global_flow_config={
		'VERILOG_FILES': [
			path.join(path.dirname(__file__), 'HW', 'core_array_new.v')
		],
		'SDC_FILE': path.join(path.dirname(__file__), 'HW', 'constraint.sdc')
	}
)

problem = vz.ProblemStatement()
problem.search_space.root.add_float_param(name='constraint_period', min_value=8, max_value=10, default_value=8) # Guessing that the optimal period is somewhere in between, based on previous results
# problem.search_space.root.add_int_param(name='ABC_MAX_FANOUT', min_value=12, max_value=28, default_value=20) # Guessing the ABC max fanout is somewhere between 12 and 28
# problem.search_space.root.add_float_param(name='ABC_MAP_EFFORT', min_value=0, max_value=1, default_value=0.6) # Guessing the ABC map effort is somewhere between 0 and 1
problem.search_space.root.add_int_param(name='n_heads', min_value=1, max_value=12, default_value=4) 
problem.search_space.root.add_int_param(name='n_cols', min_value=1, max_value=256, default_value=4) 
problem.search_space.root.add_discrete_param(name='head_dim', feasible_values=np.arange(32,288,32).tolist(), default_value=64) 
problem.search_space.root.add_discrete_param(name='max_context_length', feasible_values=np.arange(8,264,8).tolist(), default_value=64)
problem.search_space.root.add_discrete_param(name='gbus_width', feasible_values=np.arange(8,264,8).tolist(), default_value=64)

problem.metric_information.append(
    vz.MetricInformation(
        name='fom',
		goal=vz.ObjectiveMetricGoal.MINIMIZE
	)
)

study_config = vz.StudyConfig.from_problem(problem)
study_config.algorithm = 'NSGA2' # Use NSGA2 for multi-objective optimization
study_client = clients.Study.from_study_config(
  study_config,
  owner='ppa_runner',
  study_id='ppa_core_array_opt_v1'
)
print('Local SQL database file located at: ', service.VIZIER_DB_PATH)

def is_feasible(suggestion) -> bool:
	"""Check if the suggestion is feasible."""
	n_heads = int(suggestion.parameters['n_heads'])
	n_cols = int(suggestion.parameters['n_cols'])
	head_dim = int(suggestion.parameters['head_dim'])
	max_context_length = int(suggestion.parameters['max_context_length'])
	gbus_width = int(suggestion.parameters['gbus_width'])

	mac_num = int(gbus_width/8)

	if head_dim % n_cols !=0:
		print(f"head_dim {head_dim} is not divisible by n_cols {n_cols}. Reject suggestion.")
		return False
	
	core_dim = int(head_dim/n_cols)

	if core_dim % mac_num != 0:
		print(f"core_dim {core_dim} is not divisible by mac_num {mac_num}. Reject suggestion.")
		return False
	
	if max_context_length % n_cols != 0:
		print(f"max_context_length {max_context_length} is not divisible by n_heads {n_heads}. Reject suggestion.")
		return False

	return True

def fom(area: float, period: float, total_power: float):
    w1 = 0.5
    w2 = 0.5
    w3 = 0.6
    target_power = 0.8
    target_area = 3e6
    target_throughput = 6e7

    out = w1 * (area / target_area) + w2 * (total_power / target_power)

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

			run = prev_iter_ppa_runs[i]
			area = run['synth_stats']['module_area']
			period = run['ppa_stats']['sta']['clk']['clk_period']
			total_power = run['ppa_stats']['power_report']['total']['total_power']
			throughput = 1e9 / period 
    
			objective = fom(
				area=area,
				period=period,
				total_power=total_power,
			)

			print(f'Iteration {prev_iter_number}, suggestion (constraint_period = {constraint_period}')
			
			print(f'area {area} period {period} total_power {total_power} throughput {throughput} objective value {objective}.')
			final_measurement = vz.Measurement({'fom': objective})
			suggestion.complete(final_measurement)

	if prev_iter_number >= 15: # Run for 10 iterations and then stop
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
	feasible_suggestions = []
	suggestions = study_client.suggest(count=5) # Since 3 threads per job
	while len(feasible_suggestions) < 3:
		print("Generating new suggestions")
		for i, suggestion in enumerate(suggestions):
			print(suggestion.parameters)
			if not is_feasible(suggestion):
				print(f"Suggestion {i} is not feasible. Skipping.")
				# suggestion.complete(vz.Measurement(), infeasibility_reason='Infeasible design.')  # mark as completed
				suggestion.complete(vz.Measurement({'fom':math.inf}))  # mark as completed
			else:
				feasible_suggestions.append(suggestion)

	for suggestion in feasible_suggestions:
		print("Feasible suggestions:")
		print(suggestion.parameters) 
	return {
		'opt_complete': False,
		'next_suggestions': [
			{
				'flow_config': {
					'ABC_AREA': True
				},
				'hyperparameters': {
					'clk_period': suggestion.parameters['constraint_period'],
					'n_heads': int(suggestion.parameters['n_heads']),
					'n_cols': int(suggestion.parameters['n_cols']),
					'head_dim': int(suggestion.parameters['head_dim']),
					'max_context_length': int(suggestion.parameters['max_context_length']),
					'gbus_width': int(suggestion.parameters['gbus_width'])
				}
			} for suggestion in feasible_suggestions
		],
		'context': feasible_suggestions # Send suggestions as context, and they will be sent as arguments for the next run of the optimizer.
	}

ppa_runner.add_job({
	'module_name': 'core_array',
	'mode': 'opt',
	'optimizer': vizier_optimizer
})

ppa_runner.run_all_jobs() 