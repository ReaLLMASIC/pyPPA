# This is a simple optimization job example. It serves as a tutorial to the optimization mode but isn't particularly useful. See the `vizier_opt.py` example for a more complex and useful optimization example.

from os import path
import sys

sys.path.append('..')

from pyppa import PPARunner
from pyppa.tools.yosys import Yosys
from pyppa.tools.openroad import OpenROAD
from pyppa.tools.iverilog import Iverilog
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

# Read the lines below this function first, and then read this for better understanding.
def example_optimizer(prev_iter_number, prev_iter_ppa_runs, context):
	# This is a user-defined optimizer function. An optimizer function suggests sets of parameters to the PPA runner, and uses the PPA results to arrive at the most optimum set of parameters.
	# This example tries to choose a synthesis strategy that produces less than 30,000 cells in the synthesized netlist. This isn't particularly useful but serves as an example to understand the optimizer.
	# The first two arguments to this function are the previous iteration number, and the PPA results of the previous iteration. The iteration number is `0` and the results `None` for the first iteration.
	# The third argument, `context` is an optional user-defined value. See the end of this function for more information.
	if prev_iter_ppa_runs is not None:
		# Check the PPA results of the previous "runs", i.e., the PPA results for the parameter suggestions given before.
		for run in prev_iter_ppa_runs:
			if run['synth_stats']['num_cells'] < 30_000:
				# If one of the runs produced less than 30,000 cells, the optimization is successful.
				print(f"Optimum strategy found with {run['synth_stats']['num_cells']} cells. ABC_AREA={run['flow_config']['ABC_AREA']}")
				return {'opt_complete': True} # Return this dictionary to mark the end of optimization and the PPA runner will stop iterations.

	if prev_iter_number >= 2:
		# If the optimization doesn't converge after a number of iterations, it can be stopped.
		print("Optimization could not converge. Stopping optimization.")
		return {'opt_complete': True}

	# If the optimization is not complete, suggest a set of parameters to test.
	return {
		'opt_complete': False,
		# The suggestions is a list of dicts that set the flow configuration and hyperparameters.
		# Since each job is allocated multiple threads, these suggestions are run in parallel and all the results are passed as arguments during the next iteration.
		'next_suggestions': [
			# Suggest both ABC_AREA: True and False
			{
				'flow_config': {'ABC_AREA': True},
				'hyperparameters': {'clk_period': 10}
			},
			{
				'flow_config': {'ABC_AREA': False},
				'hyperparameters': {'clk_period': 10}
			}
		],
		# Context is an optional user-defined value that is passed to the next iteration. It can be used to store any global state. The context is provided as the third argument to the optimizer function. See the `vizier_opt.py` example.
		'context': {
			'foo': 'bar'
		}
	}

# Add a new optimization PPA job. This job is used to find the optimum set of parameters for given specifications. Instead of sweeping all possible configurations of the parameters, it allows checking only a subset of the parameters to arrive at the optimum solutions.
# Any optimization algorithm can be used for this purpose. The optimization function is completely user-defined and the PPA runner simply provides a way to get the PPA results for a particular set of parameters, the user-defined function is responsible for arriving at the best set of parameters.
# This example uses the function `example_optimizer()` defined above as a simple optimizer. Go check it out now. For a more complex and useful example, see the `vizier_opt.py` file.
ppa_runner.add_job({
	'module_name': 'softmax',
	'mode': 'opt',
	'optimizer': example_optimizer
})

ppa_runner.run_all_jobs()