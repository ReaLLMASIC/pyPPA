from os import path
import shutil
from .blueprint import VerilogSimTool, call_cmd

class Verilator(VerilogSimTool):
	vvp_cmd: str
	defautl_vvp_args: list[str]

	def __init__(self, scripts_dir: str, default_args: list[str] = [], cmd: str = "iverilog", default_vvp_args: list[str] = [], vvp_command: str = "vvp"):
		super().__init__(scripts_dir, default_args, cmd)
		self.defautl_vvp_args = default_vvp_args
		self.vvp_cmd = shutil.which(vvp_command)

	def run_sim(
		self,
		verilog_files: list[str],
		top_module: str,
		testbench_file: str,
		obj_dir: str,
		vcd_file: str,
		log_dir: str,
		env: dict[str, str]
	):
		objects_dir = path.join(obj_dir, 'iverilog')

		# Compile the testbench
		self._call_tool(
			args=['-o', top_module, '-s', top_module, testbench_file,  *verilog_files],
			env=env,
			logfile=path.join(log_dir, '0_1_1_iverilog_compile.log'),
			cwd=objects_dir
		)

		# Run the testbench
		call_cmd(
			cmd=self.vvp_cmd,
			args=self.defautl_vvp_args + [top_module],
			env=env,
			logfile=path.join(log_dir, '0_1_2_iverilog_run.log'),
			cwd=objects_dir
		)



