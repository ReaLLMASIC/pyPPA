from typing import TypedDict, Union, Any, Optional
from os import path, mkdir, makedirs
from shutil import rmtree
import json
from multiprocessing import Pool

from .flow import FlowRunner, FlowConfigDict, FlowTools
from .tools.blueprint import PostSynthPPAStats, PowerReport, SynthStats

from .utils.config_sweep import ParameterSweepDict, ParameterListDict, get_configs_iterator
from .utils.time import TimeElapsed, start_time_count,get_elapsed_time

class ModuleConfig(TypedDict):
	name: str
	hyperparameters: dict[str, Union[ParameterSweepDict, ParameterListDict, Any]]
	flow_config: Union[dict[str, Union[ParameterSweepDict, ParameterListDict]], FlowConfigDict]

class ModuleRun(TypedDict):
	name: str
	job_number: int
	run_dir: str
	flow_config: FlowConfigDict
	hyperparameters: dict[str, Any]

	preprocess_time: TimeElapsed

	synth_stats: SynthStats
	synth_time: TimeElapsed

	ppa_stats: PostSynthPPAStats
	power_report: PowerReport
	ppa_time: TimeElapsed

	total_time_taken: TimeElapsed

class PPARunner:
	design_name: str
	tools: FlowTools
	global_flow_config: FlowConfigDict
	modules: list[ModuleConfig]
	runs: dict[str, list[ModuleRun]] = {}
	work_home: str
	max_parallel_threads: int = 4

	def __init__(
		self,
		design_name: str,
		tools: FlowTools,
		global_flow_config: FlowConfigDict,
		modules: list[ModuleConfig],
		max_parallel_threads: int = 8,
		work_home: Optional[str] = None
	):
		self.design_name = design_name
		self.tools = tools
		self.global_flow_config = global_flow_config
		self.modules = modules
		self.work_home = work_home if work_home != None else path.abspath(path.join('.', 'runs', design_name))
		self.max_parallel_threads = max_parallel_threads

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

			# Generate module specific configs
			configs_iterator = get_configs_iterator(module['flow_config'])

			# Iterate over configs and add jobs
			job_number = 1
			for (job_flow_config, _) in configs_iterator.iterate():
				hyperparams_iterator = get_configs_iterator(module['hyperparameters'])

				# Iterate over each hyperparameter as well
				for (hyperparam_config, _) in hyperparams_iterator:
					module_work_home = path.join(self.work_home, module['name'], str(job_number))

					# Create a clean module work home
					if path.exists(module_work_home):
						rmtree(module_work_home)
					makedirs(module_work_home)

					# Write all the configurations to a file
					with open(path.join(module_work_home, 'config.json'), 'w') as config_file:
						json.dump(
							{
								'module': module['name'],
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
							**self.global_flow_config,
							**job_flow_config,
							'DESIGN_NAME': module['name'],
							'WORK_HOME': module_work_home
						},
						hyperparam_config
					)

					jobs.append((module_runner, module_work_home, job_number))
					job_number += 1

		# Run the list of jobs
		ppa_job_runner = Pool(self.max_parallel_threads)
		for run in ppa_job_runner.starmap(self.__ppa_job__, jobs):
			self.runs[run['name']].append(run)

		print(f"Completed PPA analysis. Total time elapsed: {get_elapsed_time(start_time).format()}.")

	def __ppa_job__(self, module_runner: FlowRunner, module_work_home: str, job_number: int) -> ModuleRun:
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

		print(f"Completed PPA job #{job_number}. Time taken: {total_time_taken.format()}.")

		ppa_stats = {
			'name': module_runner.get('DESIGN_NAME'),
			'job_number': job_number,
			'run_dir': module_work_home,
			'flow_config': module_runner.configopts,
			'hyperparameters': module_runner.hyperparameters,

			'preprocess_time': preprocess_time,

			'synth_stats': synth_stats,
			'synth_time': synth_time,

			'ppa_stats': ppa_stats,
			'ppa_time': ppa_time,

			'total_time_taken': total_time_taken
		}

		with open(path.join(module_work_home, 'ppa.json'), 'w') as ppa_file:
			json.dump(
				ppa_stats,
				ppa_file,
				indent=2
			)

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
