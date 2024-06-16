from typing import TypedDict, Union, Any, Optional, Callable, TypeAlias, Literal, Type
from os import path, mkdir, makedirs
from shutil import rmtree
import json
from multiprocessing import Pool
from multiprocessing.pool import Pool as PoolClass

from .flow import FlowRunner, FlowConfigDict, FlowPlatformConfigDict, FlowTools
from .tools.blueprint import PostSynthPPAStats, PowerReport, SynthStats

from .utils.config_sweep import ParameterSweepDict, ParameterListDict, get_configs_iterator
from .utils.time import TimeElapsed, start_time_count,get_elapsed_time

class NextParamsReturnType(TypedDict):
	opt_complete: bool
	flow_config: Union[FlowConfigDict, None]
	hyperparameters: Union[dict, None]

class ModuleRun(TypedDict):
	mode: Literal['sweep', 'opt']
	name: str
	"""The name of the Verilog module."""
	job_number: int
	run_dir: str
	"""The path to the directory in which the job was run."""
	flow_config: FlowConfigDict
	"""The complete flow configuration for the run."""
	hyperparameters: dict[str, Any]
	"""The set of hyperparameters used for the run."""

	preprocess_time: TimeElapsed
	"""The time taken for the preprocessing step."""

	synth_stats: SynthStats
	"""The synthesis stats."""
	synth_time: TimeElapsed
	"""The time taken for the synthesis step."""

	ppa_stats: PostSynthPPAStats
	"""The PPA stats."""
	power_report: PowerReport
	"""The power report."""
	ppa_time: TimeElapsed
	"""The time taken for the post-synthesis PPA step."""

	total_time_taken: TimeElapsed
	"""The total time elapsed in the run."""

Optimizer: TypeAlias = Callable[[int, Union[ModuleRun, None]], NextParamsReturnType]

class ModuleSweepConfig(TypedDict):
	name: str
	"""The name of the Verilog module to run the PPA analysis on."""
	mode: Literal['sweep']
	"""Either `opt` (Optimization) or `sweep`.

	In `sweep` mode, `hyperparameters` and `flow_config` dicts are provided that list either arrays of values for each parameter or a dict of `min`, `max`, and `step` to sweep. Every possible combination of the values each parameter can take will be swept and the corresponding PPA resutls will be reported."""
	hyperparameters: dict[str, Union[ParameterSweepDict, ParameterListDict, Any]]
	flow_config: Union[dict[str, Union[ParameterSweepDict, ParameterListDict]], FlowConfigDict]

class ModuleOptConfig(TypedDict):
	name: str
	"""The name of the Verilog module to run the PPA analysis on."""
	mode: Literal['opt']
	"""Either `opt` (Optimization) or `sweep`.

	In `opt` mode, the `optimizer` function provides the next set of parameters to try and the PPA results of each iteration are given as parameter to the function."""
	optimizer: Optimizer
	"""A function that evaluates the previous iteration's PPA results and suggests the next set of parameters to test. Return `{'opt_complete': True}` to mark the completion of the optimization either by meeting the target or otherwise.

	Return `{`opt_complete`: False, `flow_config`: {...}, `hyperparameters`: {...}} to suggest the next set of flow config parameters and hyperparameters to test.

	The function should accept the following arguments:
	- `iteration_number`: The iteration number for the _previous_ iteration. A `0` iteration number represents the start of the optimization and will have no PPA results.
	- `ppa_results`: A dict of type `ModuleRun` that contains the flow configuration, hyperparameters, times taken, and PPA stats of the previous iteration. The format of this dictionary is identical to the PPA results returned in the `sweep` mode.
	"""

ModuleConfig: TypeAlias = Union[ModuleSweepConfig, ModuleOptConfig]

class PPARunner:
	design_name: str
	tools: FlowTools
	platform_config: FlowPlatformConfigDict
	global_flow_config: FlowConfigDict
	modules: list[ModuleConfig]
	runs: dict[str, list[ModuleRun]] = {}
	work_home: str
	max_parallel_threads: int = 4
	job_runner: Type[PoolClass]

	def __init__(
		self,
		design_name: str,
		tools: FlowTools,
		platform_config: FlowPlatformConfigDict,
		global_flow_config: FlowConfigDict,
		modules: list[ModuleConfig],
		max_parallel_threads: int = 8,
		work_home: Optional[str] = None
	):
		self.design_name = design_name
		self.tools = tools
		self.platform_config = platform_config
		self.global_flow_config = global_flow_config
		self.modules = modules
		self.work_home = work_home if work_home != None else path.abspath(path.join('.', 'runs', design_name))
		self.max_parallel_threads = max_parallel_threads
		self.job_runner = Pool(self.max_parallel_threads)

		for module in modules:
			self.runs[module['name']] = []

	def run_ppa_analysis(self):
		start_time = start_time_count()

		# List of flow jobs to run
		jobs = []

		# Clear contents of the work home
		if path.exists(self.work_home):
			rmtree(self.work_home)
			mkdir(self.work_home)

		for module in self.modules:
			print(f"Running PPA for module `{module['name']}`.")

			if module['mode'] == "opt": # Optimization mode
				job_args: self.PPAOptJobArgs = {
					'mode': 'opt',
					'module_name': module['name'],
					'job_work_home': path.join(self.work_home, f"{module['name']}_opt"),
					'optimizer': module['optimizer']
				}

				jobs.append([job_args])
			elif module['mode'] == 'sweep': # Sweep mode
				# Generate module specific configs
				configs_iterator = get_configs_iterator(module['flow_config'])

				# Iterate over configs and add jobs
				job_number = 1
				for (job_flow_config, _) in configs_iterator.iterate():
					hyperparams_iterator = get_configs_iterator(module['hyperparameters'])

					# Iterate over each hyperparameter as well
					for (hyperparam_config, _) in hyperparams_iterator:
						module_work_home = path.join(self.work_home, f"{module['name']}_sweep", str(job_number))

						# Create a clean module work home
						if path.exists(module_work_home):
							rmtree(module_work_home)
						makedirs(module_work_home)

						# Write all the configurations to a file
						with open(path.join(module_work_home, 'config.json'), 'w') as config_file:
							json.dump(
								{
									'module': module['mode'],
									'job_number': job_number,
									'flow_config': job_flow_config,
									'hyperparameters': hyperparam_config
								},
								config_file,
								indent=2
							)

						module_runner: FlowRunner = FlowRunner(
							self.tools,
							{
								**self.platform_config,
								**self.global_flow_config,
								**job_flow_config,
								'DESIGN_NAME': module['name'],
								'WORK_HOME': module_work_home
							},
							hyperparam_config
						)

						job_args: self.PPASweepJobArgs = {
							'mode': 'sweep',
							'module_runner': module_runner,
							'module_work_home': module_work_home,
							'job_number': job_number
						}

						jobs.append([job_args])
						job_number += 1

		# Run the list of jobs
		for run in self.job_runner.starmap(self.__ppa_job__, jobs):
			self.runs[run['name']].append(run)

		print(f"Completed PPA analysis. Total time elapsed: {get_elapsed_time(start_time).format()}.")

	class PPASweepJobArgs(TypedDict):
		mode: Literal['sweep']
		module_runner: FlowRunner
		module_work_home: str
		job_number: int

	class PPAOptJobArgs(TypedDict):
		mode: Literal['opt']
		module_name: str
		job_work_home: str
		optimizer: Optimizer

	def __ppa_job__(
		self,
		job_args: Union[PPASweepJobArgs, PPAOptJobArgs]
	) -> ModuleRun:
		if job_args['mode'] == "sweep": # Sweep job
			module_runner = job_args['module_runner']
			# Preprocess platform files
			preprocess_time = module_runner.preprocess()

			# Run presynthesis simulations if enabled
			if module_runner.get('RUN_VERILOG_SIM') and module_runner.get('VERILOG_SIM_TYPE') == 'presynth':
				_, sim_time = module_runner.verilog_sim()

			# Synthesis
			synth_stats, synth_time = module_runner.synthesis()

			# Run postsynthesis simulations if enabled
			if module_runner.get('RUN_VERILOG_SIM') and module_runner.get('VERILOG_SIM_TYPE') == 'postsynth':
				_, sim_time = module_runner.verilog_sim()

			# Run post-synth PPA and generate power report
			ppa_stats, ppa_time = module_runner.postsynth_ppa()

			total_time_taken = TimeElapsed.combined(preprocess_time, synth_time, ppa_time)

			print(f"Completed PPA job #{job_args['job_number']}. Time taken: {total_time_taken.format()}.")

			ppa_stats: ModuleRun = {
				'mode': 'sweep',
				'name': module_runner.get('DESIGN_NAME'),
				'job_number': job_args['job_number'],
				'run_dir': job_args['module_work_home'],
				'flow_config': module_runner.configopts,
				'hyperparameters': module_runner.hyperparameters,

				'preprocess_time': preprocess_time,

				'synth_stats': synth_stats,
				'synth_time': synth_time,

				'ppa_stats': ppa_stats,
				'ppa_time': ppa_time,

				'total_time_taken': total_time_taken
			}

			class DefaultEncoder(json.JSONEncoder):
				def default(self, o):
					return o.__dict__

			with open(path.join(job_args['module_work_home'], 'ppa.json'), 'w') as ppa_file:
				json.dump(
					ppa_stats,
					ppa_file,
					indent=2,
					cls=DefaultEncoder
				)

			return ppa_stats
		else: # Optimization job
			prev_iter_module_run: Union[ModuleRun, None] = None
			iteration_number: int = 0

			while True: # This might be a bad idea
				iter_params = job_args['optimizer'](iteration_number, prev_iter_module_run)
				opt_complete = iter_params['opt_complete']
				iteration_number += 1

				if opt_complete:
					break

				# Create a clean iteration work home
				iter_work_home = path.join(job_args['job_work_home'], str(iteration_number))
				if path.exists(iter_work_home):
					rmtree(iter_work_home)
				makedirs(iter_work_home)

				# Write all the configurations to a file
				with open(path.join(iter_work_home, 'config.json'), 'w') as config_file:
					json.dump(
						{
							'module': job_args['module_name'],
							'iteration_number': iteration_number,
							'flow_config': iter_params['flow_config'],
							'hyperparameters': iter_params['hyperparameters']
						},
						config_file,
						indent=2
					)

				module_runner: FlowRunner = FlowRunner(
					self.tools,
					{
						**self.platform_config,
						**self.global_flow_config,
						**iter_params['flow_config'],
						'DESIGN_NAME': job_args['module_name'],
						'WORK_HOME': iter_work_home
					},
					iter_params['hyperparameters']
				)

				# Preprocess platform files
				preprocess_time = module_runner.preprocess()

				# Run presynthesis simulations if enabled
				if module_runner.get('RUN_VERILOG_SIM') and module_runner.get('VERILOG_SIM_TYPE') == 'presynth':
					_, sim_time = module_runner.verilog_sim()

				# Synthesis
				synth_stats, synth_time = module_runner.synthesis()

				# Run postsynthesis simulations if enabled
				if module_runner.get('RUN_VERILOG_SIM') and module_runner.get('VERILOG_SIM_TYPE') == 'postsynth':
					_, sim_time = module_runner.verilog_sim()

				# Run post-synth PPA and generate power report
				ppa_stats, ppa_time = module_runner.postsynth_ppa()

				total_time_taken = TimeElapsed.combined(preprocess_time, synth_time, ppa_time)

				print(f"Completed Optimization PPA iteration #{iteration_number}. Time taken: {total_time_taken.format()}.")

				prev_iter_module_run: ModuleRun = {
					'mode': 'opt',
					'name': module_runner.get('DESIGN_NAME'),
					'job_number': iteration_number,
					'run_dir': iter_work_home,
					'flow_config': module_runner.configopts,
					'hyperparameters': module_runner.hyperparameters,

					'preprocess_time': preprocess_time,

					'synth_stats': synth_stats,
					'synth_time': synth_time,

					'ppa_stats': ppa_stats,
					'ppa_time': ppa_time,

					'total_time_taken': total_time_taken
				}

				class DefaultEncoder(json.JSONEncoder):
					def default(self, o):
						return o.__dict__

				with open(path.join(iter_work_home, 'ppa.json'), 'w') as ppa_file:
					json.dump(
						prev_iter_module_run,
						ppa_file,
						indent=2,
						cls=DefaultEncoder
					)

			print(f"Optimization job complete for module {job_args['module_name']}.")
			return prev_iter_module_run

	def clean_runs(self):
		rmtree(self.global_flow_config.get('WORK_HOME'))

	def get_runs(self, module_name: str) -> list[ModuleRun]:
		return self.runs[module_name]

	def print_stats(self, file: Optional[str] = None):
		write_to = open(file, 'w') if file is not None else None

		for module_name in self.runs:
			module_runs = self.runs[module_name]
			print(f"---Module {module_name}---", file=write_to)

			for (i, run) in enumerate(module_runs):
				print(f"	Run #{i + 1}:", file=write_to)

				for stat in run['synth_stats']:
					if stat == 'cell_counts':
						# Sort the cell counts in descending order
						sorted_cell_counts = [(cell, count) for cell, count in run['synth_stats']['cell_counts'].items()]
						sorted_cell_counts.sort(key=lambda x: x[1], reverse=True)

						formatted_cell_counts = []
						for cell, count in sorted_cell_counts:
							formatted_cell_counts.append(f"{cell} ({count})")

						print(f"		{stat}: {', '.join(formatted_cell_counts)}", file=write_to)
					else:
						print(f"		{stat}: {run['synth_stats'][stat]}", file=write_to)

				for stat in run['ppa_stats']:
					if stat == 'sta':
						formatted_sta_results = []

						for clk in run['ppa_stats']['sta'].values():
							formatted_sta_results.append(f"{clk['clk_name']} (period: {clk['clk_period']}, slack: {clk['clk_slack']})")

						print(f"		{stat}: {', '.join(formatted_sta_results)}", file=write_to)
					elif stat == 'power_report':
						for power_type in run['ppa_stats'][stat]:
							formatted_power_report = [f"{metric} - {run['ppa_stats'][stat][power_type][metric]}" for metric in run['ppa_stats'][stat][power_type]]

							print(f"		{power_type} power: {', '.join(formatted_power_report)}", file=write_to)
					else:
						print(f"		{stat}: {run['ppa_stats'][stat]}", file=write_to)
