from typing import Union, TypedDict

from os import makedirs, path
from shutil import copyfile
import re

from ..tools.blueprint import SynthTool, SynthStats, APRTool, FloorplanningStats, PowerReport, VerilogSimTool
from ..tools.utils import call_util_script

from .common_config import FlowCommonConfigDict, FlowCommonConfig
from .platform_config import FlowPlatformConfigDict, FlowPlatformConfig
from .design_config import FlowDesignConfigDict, FlowDesignConfig

FlowConfigDict = Union[FlowCommonConfigDict, FlowPlatformConfigDict, FlowDesignConfigDict]

class FlowTools(TypedDict):
	verilog_sim_tool: VerilogSimTool
	synth_tool: SynthTool
	apr_tool: APRTool

class FlowRunner(FlowCommonConfig, FlowPlatformConfig, FlowDesignConfig):
	tools: FlowTools
	configopts: Union[FlowConfigDict, dict]
	config: FlowConfigDict

	def __init__(
		self,
		tools: FlowTools,
		configopts: Union[FlowConfigDict, dict]
	):
		self.tools = tools
		self.configopts = configopts.copy()
		self.config = configopts.copy()

		FlowCommonConfig.__init__(self)
		FlowPlatformConfig.__init__(self)
		FlowDesignConfig.__init__(self)

	def get(self, key: str):
		if key in self.config:
			return self.config[key]
		else:
			return None

	def set(self, key, value):
		self.config[key] = value

		self.calculate_dirs()

	def get_env(self):
		"""Returns the corresponding environment variables for the given configuration."""

		return FlowDesignConfig.get_env(
			self,
			FlowPlatformConfig.get_env(
				self,
				FlowCommonConfig.get_env(self, self.config)
			)
		)

	def preprocess(self):
		print(f"Started preprocessing for module `{self.get('DESIGN_NAME')}`.")

		# Create output directories
		makedirs(path.join(self.get('OBJECTS_DIR'), 'lib'), exist_ok = True)
		makedirs(self.get('RESULTS_DIR'), exist_ok = True)
		makedirs(self.get('REPORTS_DIR'), exist_ok = True)
		makedirs(self.get('LOG_DIR'), exist_ok = True)
		PREPROC_LOG_FILE = path.join(self.get('LOG_DIR'), '0_preprocess.log')

		# Mark libraries as dont use
		dont_use_libs = []


		for libfile in self.get('LIB_FILES'):
			output_file = path.join(self.get('OBJECTS_DIR'), 'lib', path.basename(libfile))
			call_util_script(
				'markDontUse.py',
				[
					'-p', ' '.join(self.get('DONT_USE_CELLS')),
					'-i', libfile,
					'-o', output_file
				],
				self.get('UTILS_DIR'),
				self.get_env(),
				PREPROC_LOG_FILE
			)

			dont_use_libs.append(output_file)

		self.set('DONT_USE_LIBS', dont_use_libs)
		self.set('DONT_USE_SC_LIB', self.get('DONT_USE_LIBS'))

		# Set yosys-abc clock period to first "clk_period" value or "-period" value found in sdc file
		with open(self.get('SDC_FILE')) as sdc_file:
			# Match for set clk_period or -period statements
			clk_period_matches = re.search(pattern="^set\s+clk_period\s+(\S+).*|.*-period\s+(\S+).*", flags=re.MULTILINE, string=sdc_file.read())

			if clk_period_matches is not None and len(clk_period_matches.groups()) > 0:
				self.set('ABC_CLOCK_PERIOD_IN_PS', float(clk_period_matches.group(1)))

		print(f"Preprocessing completed for module `{self.get('DESIGN_NAME')}`.")

	def pre_synth_sim(self):
		print(f"Started pre-synthesis simulations.")

		self.tools['verilog_sim_tool'].run_sim(
			verilog_files=self.get('VERILOG_FILES'),
			top_module=self.get('DESIGN_NAME'),
			testbench_file=self.get('PRESYNTH_TESTBENCH'),
			obj_dir=self.get('OBJECTS_DIR'),
			vcd_file='out.vcd',
			log_dir=self.get('LOG_DIR'),
			env=self.get_env()
		)

	def synthesis(self) -> SynthStats:
		print(f"Started synthesis for module `{self.get('DESIGN_NAME')}`.")

		SYNTH_OUTPUT_FILE = path.join(self.get('RESULTS_DIR'), '1_1_yosys.v')

		self.tools['synth_tool'].run_synth(env=self.get_env(), log_dir=self.get('LOG_DIR'))

		# Copy results
		copyfile(SYNTH_OUTPUT_FILE, path.join(self.get('RESULTS_DIR'), '1_synth.v'))
		copyfile(self.get('SDC_FILE'), path.join(self.get('RESULTS_DIR'), '1_synth.sdc'))

		print(f"Synthesis completed for {self.get('DESIGN_NAME')}.")

		with open(path.join(self.get('REPORTS_DIR'), 'synth_stat.json')) as statsfile:
			stats = self.tools['synth_tool'].parse_synth_stats(statsfile.read())

			return stats

	def floorplan(self) -> tuple[FloorplanningStats, PowerReport]:
		print(f"Started floorplanning for module `{self.get('DESIGN_NAME')}`.")

		makedirs(self.get('RESULTS_DIR'), exist_ok = True)
		makedirs(self.get('LOG_DIR'), exist_ok = True)

		self.tools['apr_tool'].run_floorplanning(self.get_env(), self.get('LOG_DIR'))

		print(f"Floorplanning completed for module `{self.get('DESIGN_NAME')}`.")

		with open(path.join(self.get('LOG_DIR'), '2_1_floorplan.log')) as logfile:
			fp_stats = self.tools['apr_tool'].parse_floorplanning_stats(raw_stats=logfile.read())

			with open(path.join(self.get('REPORTS_DIR'), '1_synth_power_report.txt')) as report_txt:
				power_report = self.tools['apr_tool'].parse_power_report(raw_report=report_txt.read())

				return fp_stats, power_report