# PyPPA - PPA Analyzer Flow In Python
PyPPA is a Python library for running Power Performance and Area (PPA) analysis and is based on the OpenROAD flow scripts. Planned features include switchable EDA tools, sweeping ranges of hyperparameters, optimization, and parallelized flows.

### Getting Started
PyPPA is entirely written in Python, except for the TCL scripts called by the EDA tools, and the platform (PDK).

#### Installation
1. Install Python dependencies.
	- `pip install -r requirements.txt`
2. Install [Python 3](https://www.python.org/).
3. Install [Yosys](https://github.com/YosysHQ/yosys) and [OpenROAD](https://github.com/the-OpenROAD-Project/openroad) by either of the following methods:
	- Install from `litex-hub` via Conda (recommended).
		1. Install [Miniconda](https://docs.anaconda.com/miniconda/miniconda-install/).
		2. Create a new environment: `conda create --name "pyppa" python=3.10`
		3. Activate the new environment: `conda activate pyppa`
		4. Run `conda install -c litex-hub yosys openroad` to install Yosys and OpenROAD.
		5. Activate the environment to use these packages each time.
	- OpenFASoC [installation guide](https://openfasoc.readthedocs.io/en/latest/getting-started.html) but it includes extra tools.
	- Since PyPPA is based on the OpenROAD flow scrips (ORFS), its [documentation](https://openroad-flow-scripts.readthedocs.io/en/latest/user/UserGuide.html) can be followed to install the tools but this also includes Klayout.
	- Build from source: [Yosys documentation](https://yosyshq.net/yosys/download.html), [OpenROAD documentation](https://openroad.readthedocs.io/en/latest/user/Build.html).
4. Optionally, install [IVerilog](https://github.com/steveicarus/iverilog) for Verilog simulations.
	- On Debian-based systems, you can install it using `apt install iverilog`. However, version >= 12.0 is preferred, especially for Systemverilog.

#### Usage
See the [simple_sweep.py](./examples/simple_sweep.py) example for a parameter-sweep example and [simple_opt.py](./examples/simple_opt.py) example for an optimization example. See [vizier_opt.py](./examples/vizier_opt.py) example a more complex optimization example using the [Vizier](https://github.com/google/vizier) optimization tool.

For a list of flow configuration options, see the file [design_config.py](./pyppa/flow/design_config.py).