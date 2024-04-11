from typing import TypedDict, Union, Optional
from os import path
from ..utils.path_utils import enumerate_dir_recursive

class __DesignCommonConfig(TypedDict):
	"""The common design configuration."""
	DESIGN_NAME: str
	"""The name of the design."""
	PLATFORM: str
	"""The process design kit to be used."""
	VERILOG_FILES: list[str]
	"""The paths to the design Verilog files."""
	SDC_FILE: str
	"""The path to design constraint (SDC) file. Default: `[design_dir]/constraint.sdc"""
	ABC_AREA: bool
	"""Whether to use `ABC_AREA` strategy for Yosys synthesis. Setting it to false will use `ABC_SPEED` strategy. Default: `False`"""
	ABC_CLOCK_PERIOD_IN_PS: float
	"""Clock period to be used by STA during synthesis. Default value read from `constraint.sdc`."""
	RUN_PRESYNTH_SIM: bool
	"""Runs pre-synthesis Verilog simulations to generate a VCD file."""
	PRESYNTH_TESTBENCH_FILES: list[str]
	"""Pre-synthesis Verilog simulation testbench files."""
	PRESYNTH_TESTBENCH_MODULE: str
	"""The Verilog module name of the pre-synthesis simulation testbench."""
	PRESYNTH_VCD_NAME: str
	"""Name of the VCD dumpfile generated in pre-synthesis simulation."""

class __DesignSynthConfig(TypedDict):
	"""The synthesis design configuration."""
	PRESERVE_CELLS: list[str]
	"""The list of cells to preserve the hierarchy of during synthesis."""
	RUN_POSTSYNTH_SIM: bool
	"""Runs post-synthesis Verilog simulations to generate a VCD file."""
	POSTSYNTH_TESTBENCH_FILES: list[str]
	"""Post-synthesis Verilog simulation testbench files."""
	POSTSYNTH_TESTBENCH_MODULE: str
	"""The Verilog module name of the post-synthesis simulation testbench."""
	POSTSYNTH_VCD_NAME: str
	"""Name of the VCD dumpfile generated in post-synthesis simulation."""

class __DesignFloorplanConfig(TypedDict):
	"""The floorplan design configuration."""
	USE_STA_VCD: bool
	"""Whether to use the synthesized VCD file for the STA power report."""
	STA_VCD_TYPE: str
	"""Whether to use the pre or post-synthesis VCD file for the STA power report. (`presynth` or `postsynth`)"""
	FLOORPLAN_DEF: str
	"""Use the DEF file to initialize floorplan."""
	DIE_AREA: tuple[float, float, float, float]
	"""The die area specified as a tuple of lower-left and upper-right corners in microns (X1,Y1,X2,Y2). This variable is ignored if `CORE_UTILIZATION` and `CORE_ASPECT_RATIO` are defined."""
	CORE_AREA: tuple[float, float, float, float]
	"""The core area specified as a tuple of lower-left and upper-right corners in microns (X1,Y1,X2,Y2). This variable is ignored if `CORE_UTILIZATION` and `CORE_ASPECT_RATIO` are defined."""
	CORE_UTILIZATION: float
	"""The core utilization percentage (0-100). Overrides `DIE_AREA` and `CORE_AREA`."""
	CORE_ASPECT_RATIO: float
	"""The core aspect ratio (height / width). This values is ignored if `CORE_UTILIZATION` undefined."""
	CORE_MARGIN: int
	"""The margin between the core area and die area, in multiples of SITE heights. The margin is applied to each side. This variable is ignored if `CORE_UTILIZATION` is undefined."""
	PLACE_PINS_ARGS: str
	"""Arguments for io pin placement."""

FlowDesignConfigDict = Union[__DesignCommonConfig, __DesignSynthConfig, __DesignFloorplanConfig]

FLOW_DESIGN_CONFIG_DEFAULTS: FlowDesignConfigDict = {
	'ABC_AREA': False,
	'ABC_CLOCK_PERIOD_IN_PS': 0,
	'PLACE_PINS_ARGS': '',
	'RUN_PRESYNTH_SIM': False
}

class FlowDesignConfig:
	configopts: Union[FlowDesignConfigDict, dict]
	config: FlowDesignConfigDict

	def __init__(self):
		# self.configopts = configopts.copy()
		self.config = {**FLOW_DESIGN_CONFIG_DEFAULTS, **self.config}

		self.config['SDC_FILE'] = self.config.get('SDC_FILE', path.join(self.config['DESIGN_DIR'], 'constraint.sdc'))

		# Set the default presynth and postsynth testbench module names as {DESIGN_NAME}_tb
		self.config['PRESYNTH_TESTBENCH_MODULE'] = self.config.get('PRESYNTH_TESTBENCH_MODULE', f"{self.config['DESIGN_NAME']}_tb")
		self.config['POSTSYNTH_TESTBENCH_MODULE'] = self.config.get('POSTSYNTH_TESTBENCH_MODULE', f"{self.config['DESIGN_NAME']}_tb")

		# Set the default presynth and postsynth dumpfile names as {DESIGN_NAME}.vcd
		self.config['PRESYNTH_VCD_NAME'] = self.config.get('PRESYNTH_VCD_NAME', f"{self.config['DESIGN_NAME']}.vcd")
		self.config['POSTSYNTH_VCD_NAME'] = self.config.get('POSTSYNTH_VCD_NAME', f"{self.config['DESIGN_NAME']}.vcd")

	def get_env(self, init_env: Optional[dict]):
		env = {**init_env} if init_env is not None else {**self.config}

		# Recursively read directories for verilog file lists
		for key in ('VERILOG_FILES', 'PRESYNTH_TESTBENCH_FILES', 'POSTSYNTH_TESTBENCH_FILES'):
			if key in self.config:
				verilog_paths = []
				for verilog_path in self.config[key]:
					if path.exists(verilog_path):
						if path.isdir(verilog_path):
							verilog_paths.extend(enumerate_dir_recursive(verilog_path))
						else:
							verilog_paths.append(verilog_path)

				env[key] = ' '.join(verilog_paths)

		# List options
		for key in ('PRESERVE_CELLS', 'DIE_AREA', 'CORE_AREA'):
			if key in self.config:
				env[key] = ' '.join(self.config[key])

		# Numeric options
		for key in ('CORE_UTILIZATION', 'CORE_ASPECT_RATIO', 'CORE_MARGIN', 'ABC_CLOCK_PERIOD_IN_PS'):
			if key in self.config:
				env[key] = str(self.config[key])

		# Boolean options (converted to integers)
		for key in ('ABC_AREA', 'RUN_PRESYNTH_SIM', 'RUN_POSTSYNTH_SIM', 'USE_STA_VCD'):
			if key in self.config:
				env[key] = str(int(self.config[key]))

		return env