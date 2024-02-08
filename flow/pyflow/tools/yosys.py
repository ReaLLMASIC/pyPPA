from os import path
from typing import TypedDict
from . import __call_tool

def __call_yosys(
	args: list[str],
	logfile: str,
	env: dict[str, str],
	yosys_cmd: str
):
	__call_tool(
		tool=yosys_cmd,
		args=['-v', '3', *args],
		env=env,
		logfile=logfile
	)

def call_yosys_script(
	script: str,
	args: list[str],
	logfile: str,
	scripts_dir: str,
	env: dict[str, str],
	yosys_cmd: str
):
	__call_yosys(["-c", path.join(scripts_dir, f'{script}.tcl'), *args], logfile, env, yosys_cmd)

class SynthStats(TypedDict):
	num_wires: int
	num_wire_bits: int
	num_public_wires: int
	num_memories: int
	num_memory_bits: int
	num_processes: int
	num_cells: int
	cell_counts: dict[str, int]
	module_area: float

def parse_yosys_synth_stats(stats_json: dict) -> SynthStats:
	stats: SynthStats = {}

	stats['num_wires'] = stats_json['design']['num_wires']
	stats['num_wire_bits'] = stats_json['design']['num_wire_bits']
	stats['num_public_wires'] = stats_json['design']['num_pub_wires']
	stats['num_public_wire_bits'] = stats_json['design']['num_pub_wire_bits']
	stats['num_memories'] = stats_json['design']['num_memories']
	stats['num_memory_bits'] = stats_json['design']['num_memory_bits']
	stats['num_processes'] = stats_json['design']['num_processes']
	stats['num_cells'] = stats_json['design']['num_cells']
	stats['module_area'] = stats_json['design']['area']
	stats['cell_counts'] = stats_json['design']['num_cells_by_type']

	return stats