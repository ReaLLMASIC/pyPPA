import json
from os import path

from .blueprint import SynthTool, SynthStats

class Yosys(SynthTool):
	def __init__(self, cmd: str, scripts_dir: str, default_args: list[str] = []):
		super().__init__(cmd, scripts_dir, default_args + ['-v', '3'])

	def run_synth(self, env: dict[str, str], log_dir: str = ""):
		self._call_tool(
			args=["-c", path.join(self.scripts_dir, f'synth.tcl')],
			env=env,
			logfile=path.join(log_dir, '1_1_yosys.log')
		)

	def parse_synth_stats(self, raw_stats: str) -> SynthStats:
		stats_json = json.loads(raw_stats)

		parsed_stats: SynthStats = {}

		parsed_stats['num_wires'] = stats_json['design']['num_wires']
		parsed_stats['num_wire_bits'] = stats_json['design']['num_wire_bits']
		parsed_stats['num_public_wires'] = stats_json['design']['num_pub_wires']
		parsed_stats['num_public_wire_bits'] = stats_json['design']['num_pub_wire_bits']
		parsed_stats['num_memories'] = stats_json['design']['num_memories']
		parsed_stats['num_memory_bits'] = stats_json['design']['num_memory_bits']
		parsed_stats['num_processes'] = stats_json['design']['num_processes']
		parsed_stats['num_cells'] = stats_json['design']['num_cells']
		parsed_stats['module_area'] = stats_json['design']['area']
		parsed_stats['cell_counts'] = stats_json['design']['num_cells_by_type']

		return parsed_stats