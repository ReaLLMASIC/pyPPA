from typing import TypedDict, Union, Any, Optional, Callable, TypeAlias, Literal, Type
from os import path, mkdir, makedirs
from shutil import rmtree
import json
from multiprocessing import Pool
from multiprocessing.pool import ThreadPool

from .flow import FlowRunner, FlowConfigDict, FlowPlatformConfigDict, FlowTools
from .tools.blueprint import PostSynthPPAStats, PowerReport, SynthStats

from .utils.config_sweep import ParameterSweepDict, ParameterListDict, get_configs_iterator
from .utils.time import TimeElapsed, start_time_count,get_elapsed_time

class OptSuggestion(TypedDict):
	flow_config: Union[FlowConfigDict, None]
	hyperparameters: Union[dict, None]

class NextParamsReturnType(TypedDict):
	opt_complete: bool
	next_suggestions: Union[list[OptSuggestion], None]

class PPARun(TypedDict):
	module_name: str
	"""The name of the Verilog module."""
	iteration_number: int
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

FlowConfigSweepDict: TypeAlias = Union[dict[str, Union[ParameterSweepDict, ParameterListDict]], FlowConfigDict]
HyperparameterSweepDict: TypeAlias = dict[str, Union[ParameterSweepDict, ParameterListDict, Any]]
class SweepJobConfig(TypedDict):
	name: str
	"""The name of the Verilog module to run the PPA analysis on."""
	mode: Literal['sweep']
	"""Either `opt` (Optimization) or `sweep`.

	In `sweep` mode, `hyperparameters` and `flow_config` dicts are provided that list either arrays of values for each parameter or a dict of `min`, `max`, and `step` to sweep. Every possible combination of the values each parameter can take will be swept and the corresponding PPA resutls will be reported."""
	hyperparameters: HyperparameterSweepDict
	flow_config: FlowConfigSweepDict
	max_threads: Union[int, None]
	"""The number of allowable threads to use for the job. The global `threads_per_job` is used if this is not set."""

Optimizer: TypeAlias = Callable[[int, Union[list[PPARun], None]], NextParamsReturnType]
class OptJobConfig(TypedDict):
	name: str
	"""The name of the Verilog module to run the PPA analysis on."""
	mode: Literal['opt']
	"""Either `opt` (Optimization) or `sweep`.

	In `opt` mode, the `optimizer` function provides the next set of parameters to try and the PPA results of each iteration are given as parameter to the function."""
	optimizer: Optimizer
	"""A function that evaluates the previous iteration's PPA results (list) and suggests the next list of set of parameters to test. Return `{'opt_complete': True}` to mark the completion of the optimization either by meeting the target or otherwise.

	Return `{`opt_complete`: False, `flow_config`: {...}, `hyperparameters`: {...}} to suggest the next set of flow config parameters and hyperparameters to test.

	The function should accept the following arguments:
	- `iteration_number`: The iteration number for the _previous_ iteration. A `0` iteration number represents the start of the optimization and will have no PPA results.
	- `ppa_results`: A list of dicts of type `PPARun` that contains the flow configuration, hyperparameters, times taken, and PPA stats of the previous iteration. The format of this dictionary is identical to the PPA results returned in the `sweep` mode.
	"""
	max_threads: Union[int, None]
	"""The number of allowable threads to use for the job. The global `threads_per_job` is used if this is not set."""

JobConfig: TypeAlias = Union[SweepJobConfig, OptJobConfig]

class JobRun(TypedDict):
	job: JobConfig
	ppa_runs: list[PPARun]

class PPARunner:
	design_name: str
	tools: FlowTools
	platform_config: FlowPlatformConfigDict
	global_flow_config: FlowConfigDict
	jobs: list[JobConfig]
	job_runs: list[JobRun] = []
	work_home: str
	max_concurrent_jobs: int = 1
	threads_per_job: int = 4
	job_runner: Type[ThreadPool]
	jobs_queue: list[Union['PPAOptJobArgs', 'PPASweepJobArgs']] = []

	def __init__(
		self,
		design_name: str,
		tools: FlowTools,
		platform_config: FlowPlatformConfigDict,
		global_flow_config: FlowConfigDict,
		jobs: list[JobConfig] = [],
		max_concurrent_jobs: int = 1,
		threads_per_job: int = 4,
		work_home: Optional[str] = None
	):
		self.design_name = design_name
		self.tools = tools
		self.platform_config = platform_config
		self.global_flow_config = global_flow_config
		self.jobs = jobs
		self.work_home = work_home if work_home != None else path.abspath(path.join('.', 'runs', design_name))
		self.max_concurrent_jobs = max_concurrent_jobs
		self.threads_per_job = threads_per_job
		self.job_runner = ThreadPool(self.max_concurrent_jobs)

	class ConfigSave(TypedDict):
		module: str
		job_number: int
		flow_config: dict
		hyperparameters: dict

	def __save_config__(
		work_home: str,
		module: str,
		iteration_number: int,
		flow_config: dict,
		hyperparameters: dict
	):
		with open(path.join(work_home, 'config.json'), 'w') as config_file:
			json.dump(
				{
					'module': module,
					'iteration_number': iteration_number,
					'flow_config': flow_config,
					'hyperparameters': hyperparameters
				},
				config_file,
				indent=2
			)

	def add_job(self, job: JobConfig):
		self.jobs.append(job)

	def run_all_jobs(self):
		start_time = start_time_count()

		# Clear contents of the work home
		if path.exists(self.work_home):
			rmtree(self.work_home)
			mkdir(self.work_home)

		while len(self.jobs) > 0:
			job = self.jobs.pop(0)

			job_work_home = path.join(self.work_home, f"{job['name']}_{job['mode']}")
			# Create a clean job work home
			if path.exists(job_work_home):
				rmtree(job_work_home)
			makedirs(job_work_home)

			print(f"Running PPA for module `{job['name']}`.")

			if job['mode'] == "opt": # Optimization mode
				job_args: self.PPAOptJobArgs = {
					'job_config': job,
					'mode': 'opt',
					'module_name': job['name'],
					'job_work_home': job_work_home,
					'max_threads': job.get('max_threads', self.threads_per_job),
					'optimizer': job['optimizer']
				}

				self.jobs_queue.append(job_args)
			elif job['mode'] == 'sweep': # Sweep mode
				job_args: self.PPASweepJobArgs = {
					'job_config': job,
					'mode': 'sweep',
					'module_name': job['name'],
					'max_threads': job.get('max_threads', self.threads_per_job),
					'job_work_home': job_work_home,
					'flow_config': job['flow_config'],
					'hyperparameters': job['hyperparameters']
				}

				self.jobs_queue.append(job_args)

		# Run the list of jobs
		self.clear_job_queue()

		print(f"Completed PPA analysis. Total time elapsed: {get_elapsed_time(start_time).format()}.")

	def clear_job_queue(self):
		"""Recursively clears the job queue. Adds new jobs (if any) to the pool once previous jobs have been cleared."""
		to_be_run = self.jobs_queue
		self.jobs_queue = []

		# Run the jobs
		job_runs = self.job_runner.starmap(self.__job_runner__, [[args] for args in to_be_run])

		self.job_runs.extend(job_runs)

		if len(self.jobs_queue) > 0:
			self.clear_job_queue()

	class PPASweepJobArgs(TypedDict):
		job_config: JobConfig
		mode: Literal['sweep']
		job_work_home: str
		module_name: str
		max_threads: int
		flow_config: FlowConfigSweepDict
		hyperparameters: HyperparameterSweepDict

	class PPAOptJobArgs(TypedDict):
		job_config: JobConfig
		mode: Literal['opt']
		job_work_home: str
		module_name: str
		max_threads: int
		optimizer: Optimizer

	def __save_ppa__(
		work_home: str,
		ppa_results: PPARun
	):
		class DefaultEncoder(json.JSONEncoder):
			def default(self, o):
				return o.__dict__

		with open(path.join(work_home, 'ppa.json'), 'w') as ppa_file:
			json.dump(
				ppa_results,
				ppa_file,
				indent=2,
				cls=DefaultEncoder
			)

	def __get_ppa_results__(
		runner: FlowRunner,
		job_number: int,
		run_dir: str
	) -> PPARun:
		# Preprocess platform files
		preprocess_time = runner.preprocess()

		# Run presynthesis simulations if enabled
		if runner.get('RUN_VERILOG_SIM') and runner.get('VERILOG_SIM_TYPE') == 'presynth':
			_, sim_time = runner.verilog_sim()

		# Synthesis
		synth_stats, synth_time = runner.synthesis()

		# Run postsynthesis simulations if enabled
		if runner.get('RUN_VERILOG_SIM') and runner.get('VERILOG_SIM_TYPE') == 'postsynth':
			_, sim_time = runner.verilog_sim()

		# Run post-synth PPA and generate power report
		ppa_stats, ppa_time = runner.postsynth_ppa()

		total_time_taken = TimeElapsed.combined(preprocess_time, synth_time, ppa_time)

		results: PPARun = {
			'name': runner.get('DESIGN_NAME'),
			'job_number': job_number,
			'run_dir': run_dir,
			'flow_config': runner.configopts,
			'hyperparameters': runner.hyperparameters,

			'preprocess_time': preprocess_time,

			'synth_stats': synth_stats,
			'synth_time': synth_time,

			'ppa_stats': ppa_stats,
			'ppa_time': ppa_time,

			'total_time_taken': total_time_taken
		}

		return results

	def __getstate__(self):
		self_dict = self.__dict__.copy()
		del self_dict['job_runner']
		return self_dict

	def __job_runner__(
		self,
		job_args: Union[PPASweepJobArgs, PPAOptJobArgs]
	) -> list[JobRun]:
		subjob_runner = Pool(job_args['max_threads'])
		subjobs = []

		if job_args['mode'] == "sweep": # Sweep job
			iteration_number = 1
			# Iterate every possible flow config
			for flow_config in get_configs_iterator(job_args['flow_config']):
				# And every hyperparameter config
				for hyperparameters in get_configs_iterator(job_args['hyperparameters']):
					flow_runner = FlowRunner()

					# Create a clean iteration work home
					iter_work_home = path.join(job_args['job_work_home'], str(iteration_number))
					if path.exists(iter_work_home):
						rmtree(iter_work_home)
					makedirs(iter_work_home)

					# Write all the configurations to a file
					PPARunner.__save_config__(
						iter_work_home,
						job_args['module_name'],
						iteration_number,
						flow_config,
						hyperparameters
					)

					# Create a flow runner for this iteration
					flow_runner: FlowRunner = FlowRunner(
						self.tools,
						{
							**self.platform_config,
							**self.global_flow_config,
							**flow_config,
							'DESIGN_NAME': job_args['module_name'],
							'WORK_HOME': iter_work_home
						},
						hyperparameters
					)

					# Add the subjob to the subjob queue
					subjobs.append((flow_runner, iter_work_home, iteration_number))

			# Run (Sweep) all the subjobs
			ppa_runs = subjob_runner.starmap(self.__ppa_runner__, subjobs)
			job_run: JobRun = {
				'job': job_args['job_config'],
				'ppa_runs': ppa_runs
			}

			return job_run
		else: # Optimization job
			prev_iter_module_runs: Union[list[PPARun], None] = None
			iteration_number = 0

			while True:
				iter_params = job_args['optimizer'](iteration_number, prev_iter_module_runs)
				opt_complete = iter_params['opt_complete']
				iteration_number += 1

				if opt_complete:
					print(f"Optimization job complete for module {job_args['module_name']}.")
					return {
						'job': job_args['job_config'],
						'ppa_runs': prev_iter_module_runs
					}

				# Create a clean iteration work home
				iter_work_home = path.join(job_args['job_work_home'], str(iteration_number))
				if path.exists(iter_work_home):
					rmtree(iter_work_home)
				makedirs(iter_work_home)

				for i, suggestion in enumerate(iter_params['next_suggestions']):
					# Create a clean suggestion work home
					suggestion_work_home = path.join(iter_work_home, str(i))
					if path.exists(suggestion_work_home):
						rmtree(suggestion_work_home)
					makedirs(suggestion_work_home)

					# Write all the configurations to a file
					PPARunner.__save_config__(
						suggestion_work_home,
						job_args['module_name'],
						iteration_number,
						suggestion['flow_config'],
						suggestion['hyperparameters']
					)

					# Create a flow runner for this iteration
					flow_runner: FlowRunner = FlowRunner(
						self.tools,
						{
							**self.platform_config,
							**self.global_flow_config,
							**suggestion['flow_config'],
							'DESIGN_NAME': job_args['module_name'],
							'WORK_HOME': suggestion_work_home
						},
						suggestion['hyperparameters']
					)

					# Add the subjob to the subjob queue
					subjobs.append((flow_runner, iter_work_home, iteration_number))

				# Run all the subjobs and give it back to the optimizer for evaluation
				prev_iter_module_runs = subjob_runner.starmap(self.__ppa_runner__, subjobs)

	def __ppa_runner__(
		self,
		flow_runner: FlowRunner,
		work_home: str,
		iteration_number: int
	) -> PPARun:
		# Get the results for this iteration
		run_results: PPARun = PPARunner.__get_ppa_results__(
			flow_runner,
			iteration_number,
			work_home
		)

		# Save and return the results for the run
		PPARunner.__save_ppa__(work_home, run_results)
		return run_results


	def clean_runs(self):
		rmtree(self.global_flow_config.get('WORK_HOME'))

	def get_sweep_runs(self, module_name: str) -> list[PPARun]:
		return self.job_runs[module_name]

	def print_stats(self, file: Optional[str] = None):
		write_to = open(file, 'w') if file is not None else None

		for module_name in self.job_runs:
			module_runs = self.job_runs[module_name]
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
