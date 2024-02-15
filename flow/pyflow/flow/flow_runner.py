from typing import Union, TypedDict

from os import makedirs, path
from shutil import copyfile
import re

from ..tools.blueprint import SynthTool, SynthStats
from ..tools.utils import call_util_script
from ..tools.openroad import do_openroad_step, parse_floorplanning_stats, parse_power_report, FloorplanningStats, PowerReport

from .common_config import FlowCommonConfigDict, FlowCommonConfig
from .platform_config import FlowPlatformConfigDict, FlowPlatformConfig
from .design_config import FlowDesignConfigDict, FlowDesignConfig

FlowConfigDict = Union[FlowCommonConfigDict, FlowPlatformConfigDict, FlowDesignConfigDict]

class FlowTools(TypedDict):
	synth_tool: SynthTool

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

	def synthesis(self) -> SynthStats:
		print(f"Started synthesis for module `{self.get('DESIGN_NAME')}`.")

		SYNTH_OUTPUT_FILE = path.join(self.get('RESULTS_DIR'), '1_1_yosys.v')

		self.tools['synth_tool'].run_synth(env=self.get_env())

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

		# STEP 1: Translate verilog to odb
		do_openroad_step('2_1_floorplan', 'floorplan', self.get('SCRIPTS_DIR'), self.get('LOG_DIR'), self.get('OPENROAD_CMD'), self.get_env())
		# STEP 2: IO Placement (random)
		do_openroad_step('2_2_floorplan_io', 'io_placement_random', self.get('SCRIPTS_DIR'), self.get('LOG_DIR'), self.get('OPENROAD_CMD'), self.get_env())
		# STEP 3: Timing Driven Mixed Sized Placement
		do_openroad_step('2_3_floorplan_tdms', 'tdms_place', self.get('SCRIPTS_DIR'), self.get('LOG_DIR'), self.get('OPENROAD_CMD'), self.get_env())
		# STEP 4: Macro Placement
		do_openroad_step('2_4_floorplan_macro', 'macro_place', self.get('SCRIPTS_DIR'), self.get('LOG_DIR'), self.get('OPENROAD_CMD'), self.get_env())
		# STEP 5: Tapcell and Welltie insertion
		do_openroad_step('2_5_floorplan_tapcell', 'tapcell', self.get('SCRIPTS_DIR'), self.get('LOG_DIR'), self.get('OPENROAD_CMD'), self.get_env())
		# STEP 6: PDN generation
		do_openroad_step('2_6_floorplan_pdn', 'pdn', self.get('SCRIPTS_DIR'), self.get('LOG_DIR'), self.get('OPENROAD_CMD'), self.get_env())

		print(f"Floorplanning completed for module `{self.get('DESIGN_NAME')}`.")

		with open(path.join(self.get('LOG_DIR'), '2_1_floorplan.log')) as logfile:
			fp_stats = parse_floorplanning_stats(log_txt=logfile.read())

			with open(path.join(self.get('REPORTS_DIR'), '1_synth_power_report.txt')) as report_txt:
				power_report = parse_power_report(report_txt=report_txt.read())

				return fp_stats, power_report