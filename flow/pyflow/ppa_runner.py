from typing import TypedDict, Union, Any, Optional
from os import path
from shutil import rmtree
from multiprocessing import Pool

from .flow import FlowRunner, FlowConfigDict
from .tools.yosys import SynthStats
from .tools.openroad import FloorplanningStats, PowerReport

class ParameterSweepDict(TypedDict):
	start: float
	end: float
	step: float

class ModuleConfig(TypedDict):
	name: str
	parameters: dict[str, Union[ParameterSweepDict, list[Any], Any]]
	flow_config: dict[str, Union[ParameterSweepDict, list[Any], Any]]

class ModuleRun(TypedDict):
	name: str
	run_dir: str
	synth_stats: SynthStats
	floorplanning_stats: FloorplanningStats
	power_report: PowerReport

class PPARunner:
	design_name: str
	global_flow_config: FlowConfigDict
	modules: list[ModuleConfig]
	runs: dict[str, list[ModuleRun]] = {}
	work_home: str
	max_parallel_threads: int = 4

	def __init__(
		self,
		design_name: str,
		global_flow_config: FlowConfigDict,
		modules: list[ModuleConfig],
		max_parallel_threads: int = 8,
		work_home: Optional[str] = None
	):
		self.design_name = design_name
		self.global_flow_config = global_flow_config
		self.modules = modules
		self.work_home = work_home if work_home != None else path.abspath(path.join('.', 'runs', design_name))
		self.max_parallel_threads = max_parallel_threads

		for module in modules:
			self.runs[module['name']] = []

	def run_ppa_analysis(self):
		jobs = []

		for module in self.modules:
			print(f"Running flow for module `{module['name']}`.")

			module_work_home = path.join(self.work_home, module['name'])
			module_runner: FlowRunner = FlowRunner({
				**self.global_flow_config,
				'DESIGN_NAME': module['name'],
				'WORK_HOME': module_work_home
			})

			jobs.append((module_runner, module_work_home))

		ppa_job_runner = Pool(self.max_parallel_threads)
		for run in ppa_job_runner.starmap(self.__ppa_job__, jobs):
			self.runs[run['name']].append(run)

	def __ppa_job__(self, module_runner: FlowRunner, module_work_home: str) -> ModuleRun:
		if path.exists(module_work_home):
			rmtree(module_work_home)

		module_runner.preprocess()

		synth_stats = module_runner.synthesis()
		fp_stats, power_report = module_runner.floorplan()

		return {
			'name': module_runner.get('DESIGN_NAME'),
			'run_dir': module_work_home,
			'synth_stats': synth_stats,
			'floorplanning_stats': fp_stats,
			'power_report': power_report
		}

	def clean_runs(self):
		rmtree(self.global_flow_config.get('WORK_HOME'))

	def print_stats(self, file: Optional[str] = None):
		write_to = open(file, 'w') if file is not None else None

		for module_name in self.runs:
			module_runs = self.runs[module_name]
			print(f"---Module {module_name}---", file=write_to)

			for (i, run) in enumerate(module_runs):
				print(f"	Run #{i + 1}:", file=write_to)

				for stat in run['synth_stats']:
					if stat == 'cell_counts':
						formatted_cell_counts = []

						for cell in run['synth_stats']['cell_counts']:
							formatted_cell_counts.append(f"{cell} ({run['synth_stats']['cell_counts'][cell]})")

						print(f"		{stat}: {', '.join(formatted_cell_counts)}", file=write_to)
					else:
						print(f"		{stat}: {run['synth_stats'][stat]}", file=write_to)

				for stat in run['floorplanning_stats']:
					if stat == 'sta':
						formatted_sta_results = []

						for clk in run['floorplanning_stats']['sta'].values():
							formatted_sta_results.append(f"{clk['clk_name']} (period: {clk['clk_period']}, slack: {clk['clk_slack']})")

						print(f"		{stat}: {', '.join(formatted_sta_results)}", file=write_to)
					else:
						print(f"		{stat}: {run['floorplanning_stats'][stat]}", file=write_to)

				for stat in run['power_report']:
					formatted_power_report = []

					for metric in run['power_report'][stat]:
						formatted_power_report.append(f"{metric} - {run['power_report'][stat][metric]}")

					print(f"		{stat}: {', '.join(formatted_power_report)}", file=write_to)