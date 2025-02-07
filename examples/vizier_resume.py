# This is a more complex and useful optimization example that uses the Vizier optimization tool by Google for running the optimization.
# See https://github.com/google/vizier for more information on Vizier.
# Install vizier using `pip install google-vizier[jax]`

from vizier import service
from vizier.service import clients
from vizier.service import pyvizier as vz
import sys
from os import path
import pickle  # For saving and loading checkpoints

sys.path.append(path.join(path.dirname(__file__), '..'))

from pyppa import PPARunner
from pyppa.tools import Yosys, OpenROAD, Iverilog
from pyppa.ppa.ppa_runner import PPARunner
from platforms.sky130hd.config import SKY130HD_PLATFORM_CONFIG

CHECKPOINT_FILE = "vizier_checkpoint.pkl"

# Load previous checkpoint if exists
def load_checkpoint():
    if path.exists(CHECKPOINT_FILE):
        with open(CHECKPOINT_FILE, "rb") as f:
            checkpoint = pickle.load(f)
        print(f"Checkpoint loaded: iteration {checkpoint['prev_iter_number']}")
        return checkpoint
    return {"prev_iter_number": 0, "previous_suggestions": None}

# Save checkpoint
def save_checkpoint(prev_iter_number, previous_suggestions):
    with open(CHECKPOINT_FILE, "wb") as f:
        pickle.dump({"prev_iter_number": prev_iter_number, "previous_suggestions": previous_suggestions}, f)
    print(f"Checkpoint saved: iteration {prev_iter_number}")

# Load checkpoint
checkpoint = load_checkpoint()
prev_iter_number = checkpoint["prev_iter_number"]
previous_suggestions = checkpoint["previous_suggestions"]

ppa_runner = PPARunner(
    design_name="softmax",
    tools={
        'verilog_sim_tool': Iverilog(scripts_dir=path.join('scripts', 'iverilog')),
        'synth_tool': Yosys(scripts_dir=path.join('scripts', 'synth')),
        'ppa_tool': OpenROAD(scripts_dir=path.join('scripts', 'ppa'))
    },
    platform_config=SKY130HD_PLATFORM_CONFIG,
    threads_per_job=3,
    global_flow_config={
        'VERILOG_FILES': [
            path.join(path.dirname(__file__), 'HW', 'softmax.v')
        ],
        'SDC_FILE': path.join(path.dirname(__file__), 'HW', 'constraint.sdc')
    }
)

problem = vz.ProblemStatement()
problem.search_space.root.add_float_param(name='constraint_period', min_value=8, max_value=15, default_value=15)
problem.search_space.root.add_float_param(name='ABC_MAP_EFFORT', min_value=0, max_value=1, default_value=0.6)
problem.search_space.root.add_discrete_param(name='num_softmax', feasible_values=[4, 8, 16, 32], default_value=8)

problem.metric_information.append(
    vz.MetricInformation(
        name='fom',
        goal=vz.ObjectiveMetricGoal.MINIMIZE
    )
)

study_config = vz.StudyConfig.from_problem(problem)
study_config.algorithm = 'DEFAULT'
study_client = clients.Study.from_study_config(
    study_config,
    owner='ppa_runner',
    study_id='ppa_softmax_optimizer_ckpt_v1'
)
print('Local SQL database file located at: ', service.VIZIER_DB_PATH)

print(study_client.trials())

# Figure of Merit function
def fom(area: float, period: float, total_power: float, num_softmax: int):
    w1 = 0.2
    w2 = 0.2
    w3 = 0.6
    target_power = 0.08
    target_area = 3e6
    target_throughput = 6e7

    throughput = 1e9 / period / num_softmax
    return w1 * (area / target_area) + w2 * (total_power / target_power) - w3 * (throughput / target_throughput)

# Optimizer function with checkpointing
def vizier_optimizer(prev_iter_number, prev_iter_ppa_runs: list[PPARunner], previous_suggestions):
    # Load past trials from Vizier
    completed_trials = study_client.trials()
    last_iteration = len(completed_trials)
    
    print(f"Found {len(completed_trials)} completed trials in history. Resuming from iteration {last_iteration}.")

    if prev_iter_ppa_runs is not None:
        if len(prev_iter_ppa_runs) != len(previous_suggestions):
            print("Number of runs does not match number of suggestions. Aborting.")
            return {'opt_complete': True}

        for i, suggestion in enumerate(previous_suggestions):
            constraint_period = suggestion.parameters['constraint_period']
            num_softmax = suggestion.parameters['num_softmax']
            map_effort = suggestion.parameters['ABC_MAP_EFFORT']

            run = prev_iter_ppa_runs[i]
            area = run['synth_stats']['module_area']
            period = run['ppa_stats']['sta']['clk']['clk_period']
            total_power = run['ppa_stats']['power_report']['total']['total_power']
            throughput = 1e9 / period / num_softmax

            objective = fom(area=area, period=period, total_power=total_power, num_softmax=num_softmax)

            print(f'Iteration {prev_iter_number}, suggestion (constraint_period = {constraint_period}, MAP_EFFORT = {map_effort}) led to')
            print(f'area {area} period {period} total_power {total_power} throughput {throughput} objective value {objective}.\n')

            final_measurement = vz.Measurement({'fom': objective})
            suggestion.complete(final_measurement)

    if prev_iter_number >= 3:
        print("Optimization complete. Printing optimal trials:")
        # Save checkpoint
        save_checkpoint(prev_iter_number + 1, suggestions)
        for optimal_trial in study_client.trials():
            optimal_trial = optimal_trial.materialize()
            print("Optimal Trial Suggestion and Objective:", optimal_trial.parameters, optimal_trial.final_measurement)
        return {'opt_complete': True}

    # Generate new suggestions
    suggestions = study_client.suggest(count=3)
    for suggestion in suggestions:
        print(suggestion.parameters)

    

    return {
        'opt_complete': False,
        'next_suggestions': [
            {
                'flow_config': {
                    'ABC_MAP_EFFORT': suggestion.parameters['ABC_MAP_EFFORT']
                },
                'hyperparameters': {
                    'clk_period': suggestion.parameters['constraint_period'],
                    'num_softmax': int(suggestion.parameters['num_softmax'])
                }
            } for suggestion in suggestions
        ],
        'context': suggestions
    }

ppa_runner.add_job({
    'module_name': 'softmax',
    'mode': 'opt',
    'optimizer': vizier_optimizer
})

ppa_runner.run_all_jobs()
