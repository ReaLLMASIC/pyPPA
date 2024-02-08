from os import path
from typing import TypedDict
import re
from . import __call_tool

def _call_openroad(args: list[str], logfile: str, openroad_cmd: str, env: dict[str, str]):
	__call_tool(
		tool=openroad_cmd,
		args=['-exit', '-no_init', *args],
		env=env,
		logfile=logfile
	)

class STAReport(TypedDict):
	clk_name: str
	clk_period: float
	clk_slack: float

class FloorplanningStats(TypedDict):
	num_sequential_cells: int
	num_combinational_cells: int
	sta: dict[str, STAReport]

def do_openroad_step(
	name: str,
	script: str,
	scripts_dir: str,
	log_dir: str,
	openroad_cmd: str,
	env: dict[str, str]
):
	script_path = path.join(scripts_dir, f'{script}.tcl')
	metricsfile_path = path.join(log_dir, f'{name}.json')
	logfile_path = path.join(log_dir, f'{name}.log')

	_call_openroad([script_path, "-metrics", metricsfile_path], logfile_path, openroad_cmd, env)

def parse_floorplanning_stats(log_txt: str) -> FloorplanningStats:
	stats: FloorplanningStats = {}

	seq_captures = re.findall('Sequential Cells Count: (\d+)', log_txt)
	stats['num_sequential_cells'] = int(seq_captures[0]) if len(seq_captures) > 0 else None

	comb_captures = re.findall('Combinational Cells Count: (\d+)', log_txt)
	stats['num_combinational_cells'] = int(comb_captures[0]) if len(comb_captures) > 0 else None

	# Capture STA results
	stats['sta'] = {}

	clk_period_captures = re.findall('Clock ([^\s]+) period ([\d\.]+)', log_txt)
	clk_slack_captures = re.findall('Clock ([^\s]+) slack ([\d\.\-]+)', log_txt)

	for (captures, prop) in [(clk_period_captures, 'clk_period'), (clk_slack_captures, 'clk_slack')]:
		for capture in captures:
			if capture[0] in stats['sta'].keys():
				stats['sta'][capture[0]][prop] = float(capture[1])
			else:
				stats['sta'][capture[0]] = {prop: float(capture[1]), 'clk_name': capture[0]}

	return stats

class PowerReportEntry(TypedDict):
	internal_power: str
	switching_power: str
	leakage_power: str
	total_power: str
	percentage: float

class PowerReportTotalPercentages(TypedDict):
	internal_power: float
	switching_power: float
	leakage_power: float

class PowerReport(TypedDict):
	sequential: PowerReportEntry
	combinational: PowerReportEntry
	clock: PowerReportEntry
	macro: PowerReportEntry
	pad: PowerReportEntry

	total: PowerReportEntry
	total_percentages: PowerReportTotalPercentages

def parse_power_report(report_txt: str) -> PowerReport:
	report: PowerReport = {}

	parse_total_percent = False
	for line in report_txt.lower().splitlines():
		values = line.split()

		for power_entry in ('sequential', 'combinational', 'clock', 'macro', 'pad', 'total'):
			if values[0] == power_entry:
				report[power_entry] = {
					'internal_power': values[1],
					'switching_power': values[2],
					'leakage_power': values[3],
					'total_power': values[4],
					'percentage': float(values[5].replace('%', ''))
				}
		if parse_total_percent:
			report['total_percentages'] = {
				'internal_power': float(values[0].replace('%', '')),
				'switching_power': float(values[1].replace('%', '')),
				'leakage_power': float(values[2].replace('%', ''))
			}
		parse_total_percent = values[0] == 'total'

	return report

