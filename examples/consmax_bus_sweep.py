from os import path
import sys

sys.path.append(path.join(path.dirname(__file__), '..'))
from pyppa import PPARunner
from pyppa.tools import Yosys, OpenROAD, Iverilog
from platforms.sky130hd.config import SKY130HD_PLATFORM_CONFIG
from collections import defaultdict

import matplotlib.pyplot as plt
import numpy as np

# Initialize a PPA runner
ppa_runner = PPARunner(
	# Design name can be anything
	design_name="consmax_bus",
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
			path.join(path.dirname(__file__), 'HW', 'consmax_bus.v')
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
	'module_name': 'consmax_bus',
	'mode': 'sweep',
	# This dictionary sets the flow configuration options for this job only. The options set here are appended to the global_flow_config options.
	# To use multiple sets of values (all of which will be swept), use a dictionary. See the option `ABC_AREA` below and `clk_period` in hyperparameters for more information.
	'flow_config': {
		# If this option is set to True, Verilgo simulations will be run using the verilog_sim_tool set above. In this example, IVerilog is used.
		'RUN_VERILOG_SIM': True,
		# This sets the netlist used for running the Verilog simulations. In this case, the postsynthesis Verilog netlist will be used.
		'VERILOG_SIM_TYPE': 'postsynth',
		# A list of the required testbench files. The design files are automatically included and need not be added here.
		'VERILOG_TESTBENCH_FILES': [path.join(path.dirname(__file__), 'HW', 'consmax_bus_tb.v')],
		# If this option is set to true, a VCD file dumped from the simulations will be used to get more accurate power estimates.
		'USE_STA_VCD': True,
		# The name of the VCD file dumped. By default it is set to `module_name.vcd`
		'VERILOG_VCD_NAME': 'consmax_bus.vcd',
		# If the option `ABC_AREA` is set to `True`, the area-optimized synthesis strategy is used as opposed to the speed-optimized strategy. The following dictionary lists both values, and hence both the options will be swept and the PPA results will be generated for each case.
		'ABC_AREA': {
			# 'values': [True, False]
			'values': [True]
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
			'start': 2,
			'end': 20,
			'step': 1
		},
		'num_head': {
			'start': 1,
			'end': 3,
			'step': 1
        }
	}
})

# Finally, run all the jobs. They will be run concurrently, and each job will be assigned a number of threads to parallelize the sweep.
# To change the number of threads assigned per job, change the `threads_per_job` argument to the PPARunner. To change the number of concurrent jobs, change the `max_concurrent_jobs` argument to the PPARunner.
ppa_runner.run_all_jobs()

clk_period = []
power = []
area = []
numofheads = []

# Reading the PPA results in Python
for job_run in ppa_runner.job_runs:
	# The `job_runs` variable contains the PPA results for each job
	for ppa_run in job_run['ppa_runs']:
		# Each job run contains multiple "PPA Runs", each of which represents a particular configuration that was swept
		clk_period.append(ppa_run['ppa_stats']['sta']['clk']['clk_period']+ppa_run['ppa_stats']['sta']['clk']['clk_slack'])
		power.append(ppa_run['ppa_stats']['power_report']['total']['total_power'])
		area.append(ppa_run['synth_stats']['module_area'])
		numofheads.append(ppa_run['hyperparameters']['num_head'])
		
		print(f"Results for run #{ppa_run['run_number']}:")
		print(f"Num of heads: {ppa_run['hyperparameters']['num_head']}")
		print(f"PPA stats: {ppa_run['ppa_stats']['power_report']['total']['total_power']} W")
		print(f"STA report: slack {ppa_run['ppa_stats']['sta']['clk']['clk_slack']} period {ppa_run['ppa_stats']['sta']['clk']['clk_period']} total {ppa_run['ppa_stats']['sta']['clk']['clk_period']+ppa_run['ppa_stats']['sta']['clk']['clk_slack']} {ppa_run['hyperparameters']['clk_period']}")
		print(f"Total cells={ppa_run['synth_stats']['num_cells']}, Area={ppa_run['synth_stats']['module_area']}, Seq/Comb cells = {ppa_run['ppa_stats']['num_sequential_cells']}/{ppa_run['ppa_stats']['num_combinational_cells']}; Synthesis strategy: {'Area' if ppa_run['flow_config']['ABC_AREA'] else 'Speed'}")

print(clk_period)
print(power)
print(area)

# coefficients = np.polyfit(clk_period, power, 2)  # 2 is the degree of the polynomial
# poly_fit = np.poly1d(coefficients)

# period_fit = np.linspace(min(clk_period), max(clk_period), 100)
# power_fit = poly_fit(period_fit)

# # plot the sweep results
# plt.figure(figsize=(10, 6))
# sc = plt.scatter(clk_period, power, c=area, cmap='Reds', s=100, alpha=0.7, edgecolors='black', marker='o', label="Data Points")
# plt.plot(period_fit, power_fit, color='red', linewidth=2, label="Poly Fit Curve (Degree 2)")
# plt.colorbar(sc, label='Area')  

# plt.xlabel('Clock Period')
# plt.ylabel('Power')
# plt.title("2D Scatter Plot with Poly Fit Curve of Clock Period, Power and Area")
# plt.legend()

# plt.savefig("plots/consmax_bus_sweep.png", format='png')

data_by_heads = defaultdict(lambda: {'clk_period': [], 'power': [], 'area': []})

for i in range(len(numofheads)):
    key = numofheads[i]
    data_by_heads[key]['clk_period'].append(clk_period[i])
    data_by_heads[key]['power'].append(power[i])
    data_by_heads[key]['area'].append(area[i])

# Create the plot
plt.figure(figsize=(10, 6))

for heads, data in data_by_heads.items():
    # Perform polynomial fit for each group
    coefficients = np.polyfit(data['clk_period'], data['power'], 2)
    poly_fit = np.poly1d(coefficients)

    # Generate fitted curve data
    period_fit = np.linspace(min(data['clk_period']), max(data['clk_period']), 100)
    power_fit = poly_fit(period_fit)

    # Plot scatter points and fit curve
    sc = plt.scatter(
        data['clk_period'], 
        data['power'], 
        c=data['area'], 
        cmap='Reds', 
        s=100, 
        alpha=0.7, 
        edgecolors='black', 
        marker='o'
        # .label=f"Num of Heads: {heads}"
    )
    plt.plot(
        period_fit, 
        power_fit, 
        linewidth=2, 
        label=f"Num of Heads: {heads}"
    )

# Add color bar for area
plt.colorbar(sc, label='Area(um^2)')

# Add labels and title
plt.xlabel('Clock Period (ns)')
plt.ylabel('Power (W)')
plt.title("Scatter Plot with Poly Fit Curves for Clock Period, Power, and Area")
plt.legend()

# Save the plot
plt.savefig("plots/consmax_bus_sweep_multiple_curves_2.png", format='png')


# plot energy per cycle v.s. Frequency
plt.figure(figsize=(10, 6))

for heads, data in data_by_heads.items():
    freq = 1000 / np.array(data['clk_period'])
    energy_per_cycle = 1000000 * np.array(data['power']) / freq

    sc = plt.scatter(
        freq, 
        energy_per_cycle, 
        c=data['area'], 
        cmap='Reds', 
        s=100, 
        alpha=0.7, 
        edgecolors='black', 
        marker='o'
        # .label=f"Num of Heads: {heads}"
    )
    plt.plot(freq, energy_per_cycle, linewidth=2, label=f"Num of Heads: {heads}")


# Add color bar for area
plt.colorbar(sc, label='Area(um^2)')

# Add labels and title
plt.xlabel('Frequency (MHz)')
plt.ylabel('Energy per cycle (pJ)')
plt.legend()

plt.savefig("plots/consmax_bus_sweep_energy_per_cycle.png", format='png')
