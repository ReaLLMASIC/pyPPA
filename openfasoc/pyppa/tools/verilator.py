from os import path
from .blueprint import VerilogSimTool
from .blueprint import call_cmd

class Verilator(VerilogSimTool):
	def __init__(self, cmd: str, scripts_dir: str, default_args: list[str] = []):
		super().__init__(cmd, scripts_dir, default_args + ['--timescale', '1ns/1ns', '--trace'])

	def run_sim(self, verilog_files: list[str], top_module: str, testbench_file: str, env: dict[str, str], vcd_file: str, log_dir: str):
		self._call_tool(
			['--top-module', top_module, '-cc', *verilog_files, '--exe', testbench_file],
			env,
			logfile=path.join(log_dir, '0_1_1_verilator_compile.log')
		)
		self.call_cmd(
			cmd='make',
			args=['-f', 'V' + top_module + '.mk', top_module],
			env=env,
			logfile=path.join(log_dir, '0_1_2_verilator_make.log')
		)
		self.call_cmd(
			cmd='./obj_dir/'+top_module,
			args=list(),
			env=env,
			logfile=path.join(log_dir, '0_1_3_verilator_exec.log')
		)

