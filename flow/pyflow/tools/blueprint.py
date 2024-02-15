import subprocess
from typing import TypedDict

def call_cmd(cmd: str, args: list[str], env: dict | None, logfile: str | None):
	for key in env:
		if type(env[key]) != str:
			print(key, env[key])

	if logfile:
		with open(logfile, 'w') as f:
			subprocess.run([cmd, *args], env=env, stdout=f, stderr=f)
	else:
		subprocess.run([cmd, *args], env=env)

class FlowTool:
	tool_cmd: str
	tool_default_args: list[str]
	scripts_dir: str

	def __init__(self, cmd: str, scripts_dir: str, default_args: list[str] = []):
		self.tool_cmd = cmd
		self.scripts_dir = scripts_dir
		self.tool_default_args = default_args

	def _call_tool(self, args: list[str], env: dict | None, logfile: str | None):
		call_cmd(
			cmd=self.tool_cmd,
			args=self.tool_default_args + args,
			env=env,
			logfile=logfile
		)

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

class SynthTool(FlowTool):
	def run_synth(self, env: dict[str, str], logfile: str):
		"""Runs the synthesis script."""
		pass

	def parse_synth_stats(self, raw_stats: str) -> SynthStats:
		"""Parses generated synthesis stats."""
		pass