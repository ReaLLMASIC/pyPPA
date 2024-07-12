from typing import Optional, Type
from os import path, mkdir, makedirs
from shutil import rmtree
import json
from multiprocessing.pool import ThreadPool

from ..flow import FlowRunner, FlowConfigDict, FlowPlatformConfigDict, FlowTools
from ..utils.time import TimeElapsed, start_time_count, get_elapsed_time

from ._types import JobConfig, JobRun, PPAJobArgs, PPARun

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
	jobs_queue: list[PPAJobArgs] = []

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

			job_work_home = path.join(self.work_home, f"{job['module_name']}_{job['mode']}")
			# Create a clean job work home
			if path.exists(job_work_home):
				rmtree(job_work_home)
			makedirs(job_work_home)

			print(f"Running PPA {'Optimization' if job['mode'] == 'opt' else 'Sweep'} job for module `{job['module_name']}`.")

			if job['mode'] == "opt": # Optimization mode
				job_args: self.PPAOptJobArgs = {
					'job_config': job,
					'mode': 'opt',
					'module_name': job['module_name'],
					'job_work_home': job_work_home,
					'max_threads': job.get('max_threads', self.threads_per_job),
					'optimizer': job['optimizer']
				}

				self.jobs_queue.append(job_args)
			elif job['mode'] == 'sweep': # Sweep mode
				job_args: self.PPASweepJobArgs = {
					'job_config': job,
					'mode': 'sweep',
					'module_name': job['module_name'],
					'max_threads': job.get('max_threads', self.threads_per_job),
					'job_work_home': job_work_home,
					'flow_config': job['flow_config'],
					'hyperparameters': job['hyperparameters']
				}

				self.jobs_queue.append(job_args)

		# Run the list of jobs
		self.__clear_job_queue__()

		print(f"Completed all jobs. Total time elapsed: {get_elapsed_time(start_time).format()}.")

	from ._job_queue import __clear_job_queue__

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
			'module_name': runner.get('DESIGN_NAME'),
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
