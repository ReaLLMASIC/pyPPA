from os import path
import re
from .blueprint import APRTool, FloorplanningStats, PowerReport

class OpenROAD(APRTool):
	def __init__(self, scripts_dir: str, default_args: list[str] = [], cmd: str = 'openroad'):
		super().__init__(scripts_dir, default_args + ['-exit', '-no_init'], cmd)

	def __run_step(self, step_name: str, script: str, env: dict[str, str], log_dir: str):
		script_path = path.join(self.scripts_dir, f'{script}.tcl')
		metricsfile_path = path.join(log_dir, f'{step_name}.json')
		logfile_path = path.join(log_dir, f'{step_name}.log')

		self._call_tool([script_path, "-metrics", metricsfile_path], env, logfile_path)

	def run_floorplanning(self, env: dict[str, str], log_dir: str = ""):
		# STEP 1: Translate verilog to odb
		self.__run_step('2_1_floorplan', 'floorplan', env, log_dir)
		# STEP 2: IO Placement (random)
		self.__run_step('2_2_floorplan_io', 'io_placement_random', env, log_dir)
		# STEP 3: Timing Driven Mixed Sized Placement
		self.__run_step('2_3_floorplan_tdms', 'tdms_place', env, log_dir)
		# STEP 4: Macro Placement
		self.__run_step('2_4_floorplan_macro', 'macro_place', env, log_dir)
		# STEP 5: Tapcell and Welltie insertion
		self.__run_step('2_5_floorplan_tapcell', 'tapcell', env, log_dir)
		# STEP 6: PDN generation
		self.__run_step('2_6_floorplan_pdn', 'pdn', env, log_dir)

	def parse_floorplanning_stats(self, raw_stats: str) -> FloorplanningStats:
		parsed_stats: FloorplanningStats = {}

		seq_captures = re.findall('Sequential Cells Count: (\d+)', raw_stats)
		parsed_stats['num_sequential_cells'] = int(seq_captures[0]) if len(seq_captures) > 0 else None

		comb_captures = re.findall('Combinational Cells Count: (\d+)', raw_stats)
		parsed_stats['num_combinational_cells'] = int(comb_captures[0]) if len(comb_captures) > 0 else None

		# Capture STA results
		parsed_stats['sta'] = {}

		clk_period_captures = re.findall('Clock ([^\s]+) period ([\d\.]+)', raw_stats)
		clk_slack_captures = re.findall('Clock ([^\s]+) slack ([\d\.\-]+)', raw_stats)

		for (captures, prop) in [(clk_period_captures, 'clk_period'), (clk_slack_captures, 'clk_slack')]:
			for capture in captures:
				if capture[0] in parsed_stats['sta'].keys():
					parsed_stats['sta'][capture[0]][prop] = float(capture[1])
				else:
					parsed_stats['sta'][capture[0]] = {prop: float(capture[1]), 'clk_name': capture[0]}

		return parsed_stats

	def parse_power_report(self, raw_report: str) -> PowerReport:
		parsed_report: PowerReport = {}

		parse_total_percent = False
		for line in raw_report.lower().splitlines():
			values = line.split()

			for power_entry in ('sequential', 'combinational', 'clock', 'macro', 'pad', 'total'):
				if values[0] == power_entry:
					parsed_report[power_entry] = {
						'internal_power': values[1],
						'switching_power': values[2],
						'leakage_power': values[3],
						'total_power': values[4],
						'percentage': float(values[5].replace('%', ''))
					}
			if parse_total_percent:
				parsed_report['total_percentages'] = {
					'internal_power': float(values[0].replace('%', '')),
					'switching_power': float(values[1].replace('%', '')),
					'leakage_power': float(values[2].replace('%', ''))
				}
			parse_total_percent = values[0] == 'total'

		return parsed_report