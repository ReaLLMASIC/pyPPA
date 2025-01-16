from os import path
import sys
import numpy as np
import matplotlib.pyplot as plt

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
		# The constraint SDC file path.
		'SDC_FILE': path.join(path.dirname(__file__), 'HW', 'constraint.sdc')
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
			'values': [True]
		}
		,'ABC_MAX_FANOUT': {
			'start': 12,
			'end': 28,
			'step': 4
		},
		'ABC_MAP_EFFORT': {
			'values': [0.5]
		},
		'ABC_AREC_EFFORT': {
            'values': [0.5]
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
			'values': [12.5]
		}
	}
})

# Finally, run all the jobs. They will be run concurrently, and each job will be assigned a number of threads to parallelize the sweep.
# To change the number of threads assigned per job, change the `threads_per_job` argument to the PPARunner. To change the number of concurrent jobs, change the `max_concurrent_jobs` argument to the PPARunner.
ppa_runner.run_all_jobs()

clk_period = []
power = []
area = []

# Reading the PPA results in Python
for job_run in ppa_runner.job_runs:
	# The `job_runs` variable contains the PPA results for each job
	for ppa_run in job_run['ppa_runs']:
		# Each job run contains multiple "PPA Runs", each of which represents a particular configuration that was swept
		clk_period.append(ppa_run['ppa_stats']['sta']['clk']['clk_period'])
		power.append(ppa_run['ppa_stats']['power_report']['total']['total_power'])
		area.append(ppa_run['synth_stats']['module_area'])
		
		print(f"Results for run #{ppa_run['run_number']}:")
		print(f"ABC max fanout: {ppa_run['flow_config']['ABC_MAX_FANOUT']}")  # This is the value of the ABC_MAX_FANOUT option
		print(f"ABC map effort: {ppa_run['flow_config']['ABC_MAP_EFFORT']}")  # This is the value of the ABC_MAP_EFFORT option
		print(f"PPA stats: {ppa_run['ppa_stats']['power_report']['total']['total_power']} W")
		print(f"STA report: slack {ppa_run['ppa_stats']['sta']['clk']['clk_slack']} period {ppa_run['ppa_stats']['sta']['clk']['clk_period']} total {ppa_run['ppa_stats']['sta']['clk']['clk_period']+ppa_run['ppa_stats']['sta']['clk']['clk_slack']}")
		print(f"Total cells={ppa_run['synth_stats']['num_cells']}, Area={ppa_run['synth_stats']['module_area']}, Seq/Comb cells = {ppa_run['ppa_stats']['num_sequential_cells']}/{ppa_run['ppa_stats']['num_combinational_cells']}; Synthesis strategy: {'Area' if ppa_run['flow_config']['ABC_AREA'] else 'Speed'}")

print(clk_period)
print(power)
print(area)

coefficients = np.polyfit(clk_period, power, 2)  # 2 is the degree of the polynomial
poly_fit = np.poly1d(coefficients)

period_fit = np.linspace(min(clk_period), max(clk_period), 100)
power_fit = poly_fit(period_fit)

# plot the sweep results
plt.figure(figsize=(10, 6))
sc = plt.scatter(clk_period, power, c=area, cmap='Reds', s=100, alpha=0.7, edgecolors='black', marker='o', label="OpenROAD")
plt.plot(period_fit, power_fit, color='red', linewidth=2)

plt.colorbar(sc, label='Area(um^2)')  

plt.xlabel('Clock Period(ns)')
plt.ylabel('Power(W)')
plt.title("2D Scatter Plot with Poly Fit Curve of Clock Period, Power and Area")
plt.legend()


plt.savefig("plots/softmax_sweep_compare.png", format='png')
