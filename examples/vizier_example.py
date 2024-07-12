# Install vizier using `pip install google-vizier[jax]`

from vizier import service
from vizier.service import clients
from vizier.service import pyvizier as vz

from os import path

from pyppa import PPARunner
from pyppa.ppa.ppa_runner import PPARun
from pyppa.tools.yosys import Yosys
from pyppa.tools.openroad import OpenROAD
from pyppa.tools.iverilog import Iverilog
from config import SKY130HD_PLATFORM_CONFIG

softmax_runner = PPARunner(
	design_name="softmax",
	tools={
		'verilog_sim_tool': Iverilog(scripts_dir=path.join('scripts', 'iverilog')),
		'synth_tool': Yosys(scripts_dir=path.join('scripts', 'synth')),
		'ppa_tool': OpenROAD(scripts_dir=path.join('scripts', 'ppa'))
	},
	platform_config=SKY130HD_PLATFORM_CONFIG,
	threads_per_job=3,
	global_flow_config={
		'PLATFORM': 'sky130hd',
		'VERILOG_FILES': [
			path.join(path.dirname(__file__), 'HW', 'softmax.v')
		],
		'DESIGN_DIR': path.join(path.dirname(__file__), 'HW')
	}
)

problem = vz.ProblemStatement()
problem.search_space.root.add_float_param('constraint_period', 5, 15) # Guessing that the optimal period is somewhere in between, based on previous results
problem.search_space.root.add_bool_param('abc_area')
problem.metric_information.append(
    vz.MetricInformation(
        name='fom',
		goal=vz.ObjectiveMetricGoal.MAXIMIZE
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

def fom(area: float, period: float, constraint_period: float, total_power: float):
	area_in_mm2 = area / 1000_000 # Convert um^2 area into mm^2

	# We try to reduce the slack to 0 to get the optimum period
	# While also trying to reduce the area and the total power (which increases with reducing period)
	slack = abs(constraint_period - period)
	return 1 / (area_in_mm2 * period * total_power * slack)

def vizier_optimizer(prev_iter_number, prev_iter_ppa_runs: list[PPARun], previous_suggestions):
	if prev_iter_ppa_runs is not None:
		if len(prev_iter_ppa_runs) != len(previous_suggestions):
			print("Number of runs does not match number of suggestions. Something went wrong, aborting.")
			return {
				'opt_complete': True
			}

		for i, suggestion in enumerate(previous_suggestions):
			constraint_period = suggestion.parameters['constraint_period']
			abc_area = suggestion.parameters['abc_area']

			run = prev_iter_ppa_runs[i]
			objective = fom(
				area=run['synth_stats']['module_area'],
				period=run['ppa_stats']['sta']['clk']['clk_period'],
				constraint_period=constraint_period,
				total_power=run['ppa_stats']['power_report']['total']['total_power']
			)

			print(f'Iteration {prev_iter_number}, suggestion (constraint_period = {constraint_period}, abc_area = {abc_area}) led to objective value {objective}.')
			final_measurement = vz.Measurement({'fom': objective})
			suggestion.complete(final_measurement)

	if prev_iter_number >= 10: # Go for 10 iterations
		print("Optimization complete.")
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
	return {
			'opt_complete': False,
			'next_suggestions': [
				{
					'flow_config': {
						'ABC_AREA': bool(suggestion.parameters['abc_area'])
					},
					'hyperparameters': {
						'clk_period': suggestion.parameters['constraint_period']
					}
				} for suggestion in suggestions
			],
			'context': suggestions # Send suggestions as context, and they will be sent as arguments for the next run of the optimizer.
		}

softmax_runner.add_job({
	'module_name': 'softmax',
	'mode': 'opt',
	'optimizer': vizier_optimizer
})

softmax_runner.run_all_jobs()