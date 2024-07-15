from typing import TypedDict, Union, Optional
from os import path

class __FlowConfigDirectories(TypedDict):
	"""The flow directories."""
	FLOW_HOME: str
	"""The home directory for the flow scripts. Default: `.`"""
	WORK_HOME: str
	"""The directory in which all the outputs are generated."""
	UTILS_DIR: str
	"""The directory in which util functions are stored. Default: `[flow_home]/util/`"""
	SCRIPTS_DIR: str
	"""The directory in which the scripts are stored. Default: `[flow_home]/scripts/`"""
	RESULTS_DIR: str
	"""The directory in which all flow results will be generated. Default: `[flow_home]/results/[platform]/[design_name]/`"""
	LOG_DIR: str
	"""The directory in which all log files will be generated. Default: `[flow_home]/logs/[platform]/[design_name]/`"""
	REPORTS_DIR: str
	"""The directory in which all reports will be generated. Default: `[flow_home]/reports/[platform]/[design_name]/`"""
	OBJECTS_DIR: str
	"""The directory in which all objects will be generated. Default: `[flow_home]/objects/[platform]/[design_name]/`"""

class __FlowConfigTools(TypedDict):
	"""The tool configurations."""

	# SYNTHESIS CONFIG
	SYNTH_ARGS: str
	"""Optional synthesis variables for Yosys."""
	SYNTH_HIERARCHICAL: str

FlowCommonConfigDict = Union[__FlowConfigDirectories, __FlowConfigTools]

FLOW_COMMON_CONFIG_DEFAULTS: FlowCommonConfigDict = {
	'FLOW_HOME': path.abspath('.'),
	'WORK_HOME': path.abspath('.'),
	'SYNTH_ARGS': '-flatten'
}

class FlowCommonConfig:
	configopts: Union[FlowCommonConfigDict, dict]
	config: FlowCommonConfigDict

	def __init__(self):
		# self.configopts = configopts.copy()
		self.config = {**FLOW_COMMON_CONFIG_DEFAULTS, **self.config}

		self.calculate_dirs()

	def calculate_dirs(self):
		# Set defaults for static directories
		self.config['UTILS_DIR'] = self.configopts.get('UTILS_DIR', path.join(self.config['FLOW_HOME'], 'util'))
		self.config['SCRIPTS_DIR'] = self.configopts.get('SCRIPTS_DIR', path.join(self.config['FLOW_HOME'], 'scripts'))

		# Set defaults for generated directories
		self.config['RESULTS_DIR'] = self.configopts.get('RESULTS_DIR', path.join(self.config['WORK_HOME'], 'results'))
		self.config['LOG_DIR'] = self.configopts.get('LOG_DIR', path.join(self.config['WORK_HOME'], 'logs'))
		self.config['REPORTS_DIR'] = self.configopts.get('REPORTS_DIR', path.join(self.config['WORK_HOME'], 'reports'))
		self.config['OBJECTS_DIR'] = self.configopts.get('OBJECTS_DIR', path.join(self.config['WORK_HOME'], 'objects'))

	def get_env(self, init_env: Optional[dict]):
		env = {**init_env} if init_env is not None else {**self.config}

		return env
