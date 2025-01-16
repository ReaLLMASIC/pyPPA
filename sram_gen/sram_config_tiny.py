# Data word size
word_size = 16
# Number of words in the memory
num_words = 512

# Technology to use in $OPENRAM_TECH
tech_name = "sky130"
# Process corners to characterize
process_corners = [ "TT" ]
# Voltage corners to characterize
supply_voltages = [ 3.3 ]
# Temperature corners to characterize
temperatures = [ 25 ]

# Output directory for the results
output_path = "output"
# Output file base name
output_name = "sram_16x512"

# Disable analytical models for full characterization (WARNING: slow!)
# analytical_delay = False

num_spare_cols = 1
num_spare_rows = 1

import os
exec(open(os.path.join(os.path.dirname(__file__), 'sky130_sram_common.py')).read())
