from typing import TypedDict, Union, Any, Optional
from os import path
from shutil import rmtree
from multiprocessing import Pool

from .flow import FlowRunner, FlowConfigDict
from .tools.yosys import SynthStats
from .tools.openroad import FloorplanningStats

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
		fp_stats = module_runner.floorplan()

		return {
			'name': module_runner.get('DESIGN_NAME'),
			'run_dir': module_work_home,
			'synth_stats': synth_stats,
			'floorplanning_stats': fp_stats
		}

	def clean_runs(self):
		rmtree(self.global_flow_config.get('WORK_HOME'))

	def print_stats(self):
		for module_name in self.runs:
			module_runs = self.runs[module_name]
			print(f"---Module {module_name}---")

			for (i, run) in enumerate(module_runs):
				print(f"	Run #{i + 1}:")

				for stat in run['synth_stats']:
					if stat == 'cell_counts':
						formatted_cell_counts = []

						for cell in run['synth_stats']['cell_counts']:
							formatted_cell_counts.append(f"{cell} ({run['synth_stats']['cell_counts'][cell]})")

						print(f"		{stat}: {', '.join(formatted_cell_counts)}")
					else:
						print(f"		{stat}: {run['synth_stats'][stat]}")

				for stat in run['floorplanning_stats']:
					if stat == 'sta':
						formatted_sta_results = []

						for clk in run['floorplanning_stats']['sta'].values():
							formatted_sta_results.append(f"{clk['clk_name']} (period: {clk['clk_period']}, slack: {clk['clk_slack']})")

						print(f"		{stat}: {', '.join(formatted_sta_results)}")
					else:
						print(f"		{stat}: {run['floorplanning_stats'][stat]}")