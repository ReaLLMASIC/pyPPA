from typing import Union

from os import makedirs, path
from shutil import copyfile
import re
import json

from ..tools.yosys import call_yosys_script, parse_yosys_synth_stats, SynthStats
from ..tools.utils import call_util_script
from ..tools.openroad import do_openroad_step, parse_floorplanning_stats, FloorplanningStats

from .common_config import FlowCommonConfigDict, FlowCommonConfig
from .platform_config import FlowPlatformConfigDict, FlowPlatformConfig
from .design_config import FlowDesignConfigDict, FlowDesignConfig

FlowConfigDict = Union[FlowCommonConfigDict, FlowPlatformConfigDict, FlowDesignConfigDict]

class FlowRunner(FlowCommonConfig, FlowPlatformConfig, FlowDesignConfig):
	configopts: Union[FlowConfigDict, dict]
	config: FlowConfigDict

	def __init__(self, configopts: Union[FlowConfigDict, dict]):
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
		SYNTH_LOG_FILE = path.join(self.get('LOG_DIR'), '1_1_yosys.log')

		call_yosys_script(
			'synth',
			logfile=SYNTH_LOG_FILE,
			args=[],
			scripts_dir=self.get('SCRIPTS_DIR'),
			env=self.get_env(),
			yosys_cmd=self.get('YOSYS_CMD')
		)

		# Copy results
		copyfile(SYNTH_OUTPUT_FILE, path.join(self.get('RESULTS_DIR'), '1_synth.v'))
		copyfile(self.get('SDC_FILE'), path.join(self.get('RESULTS_DIR'), '1_synth.sdc'))

		print(f"Synthesis completed for {self.get('DESIGN_NAME')}.")

		with open(path.join(self.get('REPORTS_DIR'), 'synth_stat.json')) as statsfile:
			stats_json = json.loads(statsfile.read())
			stats = parse_yosys_synth_stats(stats_json)

			return stats

	def floorplan(self) -> FloorplanningStats:
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
			return parse_floorplanning_stats(log_txt=logfile.read())