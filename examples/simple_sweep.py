from os import path
import sys

sys.path.append(path.join(path.dirname(__file__), '..'))
from pyppa import PPARunner
from pyppa.tools import Yosys, OpenROAD, Iverilog
from platforms.sky130hd.config import SKY130HD_PLATFORM_CONFIG

# Initialize a PPA runner
ppa_runner = PPARunner(
	# Design name can be anything
	design_name="softmax",
	# Define the tools to be used here
	tools={
		'verilog_sim_tool': Iverilog(scripts_dir=path.join('scripts', 'iverilog')),
		'synth_tool': Yosys(scripts_dir=path.join('scripts', 'synth')),
		'ppa_tool': OpenROAD(scripts_dir=path.join('scripts', 'ppa'))
	},
	# The global flow configuration that applies to all jobs
	global_flow_config={
		# Source Verilog files.
		'VERILOG_FILES': [
			path.join(path.dirname(__file__), 'HW', 'softmax.v')
		],
		# The directory in which the source files are. The constraint.sdc file is read from this directory.
		'DESIGN_DIR': path.join(path.dirname(__file__), 'HW')
	}
)

# Set the platform configuration
ppa_runner.set_platform(SKY130HD_PLATFORM_CONFIG)

# Add a new sweep PPA job. This job sweeps a range of flow configurations and hyperparameters
ppa_runner.add_job({
	# Name of the Verilog module to run the PPA job on
	'module_name': 'softmax',
	'mode': 'sweep',
	# This dictionary sets the flow configuration options for this job only. The options set here are appended to the global_flow_config options.
	# To use multiple sets of values (all of which will be swept), use a dictionary. See the option `ABC_AREA` below and `clk_period` in hyperparameters for more information.
	'flow_config': {
		# If this option is set to True, Verilgo simulations will be run using the verilog_sim_tool set above. In this example, IVerilog is used.
		'RUN_VERILOG_SIM': True,
		# This sets the netlist used for running the Verilog simulations. In this case, the postsynthesis Verilog netlist will be used.
		'VERILOG_SIM_TYPE': 'postsynth',
		# A list of the required testbench files. The design files are automatically included and need not be added here.
		'VERILOG_TESTBENCH_FILES': [path.join(path.dirname(__file__), 'HW', 'softmax_tb.v')],
		# If this option is set to true, a VCD file dumped from the simulations will be used to get more accurate power estimates.
		'USE_STA_VCD': True,
		# The name of the VCD file dumped. By default it is set to `module_name.vcd`
		'VERILOG_VCD_NAME': 'softmax.vcd',
		# If the option `ABC_AREA` is set to `True`, the area-optimized synthesis strategy is used as opposed to the speed-optimized strategy. The following dictionary lists both values, and hence both the options will be swept and the PPA results will be generated for each case.
		'ABC_AREA': {
			'values': [True, False]
		}
	},
	# Hyperparameters are used defined parameters that can be inserted in the source files using the Mako templating syntax. See https://www.makotemplates.org/ for more information.
	# The simplest way is to write ${clk_period} in any source files (Verilog, Verilog testbench file, or constraint.sdc) to replace the value with the parameters set.
	# See the constraint.sdc file for example syntax usage.
	# The hyperparameters are swept along with the flow config, and all possible combinations of the options will be swept.
	'hyperparameters': {
		# The dictionary below defines a sweep for the `clk_period` hyperparameter. All values of clk_period, starting at `10` and going upto `100` will be swept with a step of 10. i.e., 10, 20, ..., 100.
		# This hyperparameter is used to set the clock period in the constraint.sdc and the verilog testbench.
		'clk_period': {
			'start': 10,
			'end': 100,
			'step': 10
		}
	}
})

# Finally, run all the jobs. They will be run concurrently, and each job will be assigned a number of threads to parallelize the sweep.
# To change the number of threads assigned per job, change the `threads_per_job` argument to the PPARunner. To change the number of concurrent jobs, change the `max_concurrent_jobs` argument to the PPARunner.
ppa_runner.run_all_jobs()