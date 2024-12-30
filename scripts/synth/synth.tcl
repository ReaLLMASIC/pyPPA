source $::env(SCRIPTS_DIR)/synth_preamble.tcl

# set buffering $::env(SYNTH_BUFFERING)
# set sizing $::env(SYNTH_SIZING)

set buffering 1
set sizing 1

# input pin cap of IN_3VX8
# set max_FO $::env(MAX_FANOUT_CONSTRAINT)
# set max_TR 0
# if { [info exist ::env(MAX_TRANSITION_CONSTRAINT)]} {
#     set max_TR [expr {$::env(MAX_TRANSITION_CONSTRAINT) * 1000}]; # ns -> ps
# }

set max_FO 10
set max_TR 0

# Generic synthesis
set final_synth_args $::env(SYNTH_ARGS)
if {[info exists ::env(SYNTH_HIERARCHICAL)] && $::env(SYNTH_HIERARCHICAL) != 1} {
  puts "Flattening the hierarchy."
  append final_synth_args " -flatten"
}
synth  -top $::env(DESIGN_NAME) {*}$final_synth_args

if { [info exists ::env(USE_LSORACLE)] } {
    set lso_script [open $::env(OBJECTS_DIR)/lso.script w]
    puts $lso_script "ps -a"
    puts $lso_script "oracle --config $::env(LSORACLE_KAHYPAR_CONFIG)"
    puts $lso_script "ps -m"
    puts $lso_script "crit_path_stats"
    puts $lso_script "ntk_stats"
    close $lso_script

    # LSOracle synthesis
    lsoracle -script $::env(OBJECTS_DIR)/lso.script -lso_exe $::env(LSORACLE_CMD)
    techmap
}

# Optimize the design
opt -purge

# Technology mapping of adders
if {[info exist ::env(ADDER_MAP_FILE)] && [file isfile $::env(ADDER_MAP_FILE)]} {
  # extract the full adders
  extract_fa
  # map full adders
  techmap -map $::env(ADDER_MAP_FILE)
  techmap
  # Quick optimization
  opt -fast -purge
}

# Technology mapping of latches
if {[info exist ::env(LATCH_MAP_FILE)]} {
  techmap -map $::env(LATCH_MAP_FILE)
}

# Technology mapping of flip-flops
# dfflibmap only supports one liberty file
if {[info exist ::env(DFF_LIB_FILE)]} {
  dfflibmap -liberty $::env(DFF_LIB_FILE)
} else {
  dfflibmap -liberty $::env(DONT_USE_SC_LIB)
}
opt

set constr [open $::env(OBJECTS_DIR)/abc.constr w]
puts $constr "set_driving_cell $::env(ABC_DRIVER_CELL)"
puts $constr "set_load $::env(ABC_LOAD_IN_FF)"
close $constr

# Mapping parameters
set A_factor  0.00
set B_factor  0.88
set F_factor  0.00

# Assemble Scripts (By Strategy)
set abc_rs_K    "resub,-K,"
set abc_rs      "resub"
set abc_rsz     "resub,-z"
set abc_rf      "drf,-l"
set abc_rfz     "drf,-l,-z"
set abc_rw      "drw,-l"
set abc_rwz     "drw,-l,-z"
set abc_rw_K    "drw,-l,-K"
# if { $::env(SYNTH_ABC_LEGACY_REFACTOR) == "1" } {
#     set abc_rf      "refactor"
#     set abc_rfz     "refactor,-z"
# }
# if { $::env(SYNTH_ABC_LEGACY_REWRITE) == "1" } {
#     set abc_rw      "rewrite"
#     set abc_rwz     "rewrite,-z"
#     set abc_rw_K    "rewrite,-K"
# }
set abc_b       "balance"

set abc_resyn2        "${abc_b}; ${abc_rw}; ${abc_rf}; ${abc_b}; ${abc_rw}; ${abc_rwz}; ${abc_b}; ${abc_rfz}; ${abc_rwz}; ${abc_b}"
set abc_share         "strash; multi,-m; ${abc_resyn2}"
set abc_resyn2a       "${abc_b};${abc_rw};${abc_b};${abc_rw};${abc_rwz};${abc_b};${abc_rwz};${abc_b}"
set abc_resyn3        "balance;resub;resub,-K,6;balance;resub,-z;resub,-z,-K,6;balance;resub,-z,-K,5;balance"
set abc_resyn2rs      "${abc_b};${abc_rs_K},6;${abc_rw};${abc_rs_K},6,-N,2;${abc_rf};${abc_rs_K},8;${abc_rw};${abc_rs_K},10;${abc_rwz};${abc_rs_K},10,-N,2;${abc_b},${abc_rs_K},12;${abc_rfz};${abc_rs_K},12,-N,2;${abc_rwz};${abc_b}"

set abc_choice        "fraig_store; ${abc_resyn2}; fraig_store; ${abc_resyn2}; fraig_store; fraig_restore"
set abc_choice2      "fraig_store; balance; fraig_store; ${abc_resyn2}; fraig_store; ${abc_resyn2}; fraig_store; ${abc_resyn2}; fraig_store; fraig_restore"

set abc_map_old_cnt			"map,-p,-a,-B,0.2,-A,0.9,-M,0"
set abc_map_old_dly         "map,-p,-B,0.2,-A,0.9,-M,0"
set abc_retime_area         "retime,-D,{D},-M,5"
set abc_retime_dly          "retime,-D,{D},-M,6"
set abc_map_new_area        "amap,-m,-Q,0.1,-F,20,-A,20,-C,5000"

set abc_area_recovery_1       "${abc_choice}; map;"
set abc_area_recovery_2       "${abc_choice2}; map;"

set map_old_cnt			    "map,-p,-a,-B,0.2,-A,0.9,-M,0"
set map_old_dly			    "map,-p,-B,0.2,-A,0.9,-M,0"
set abc_retime_area   	"retime,-D,{D},-M,5"
set abc_retime_dly    	"retime,-D,{D},-M,6"
set abc_map_new_area  	"amap,-m,-Q,0.1,-F,20,-A,20,-C,5000"

if {$buffering==1} {
    set max_tr_arg ""
    if { $max_TR != 0 } {
        set max_tr_arg ",-S,${max_TR}"
    }
    set abc_fine_tune		"buffer,-N,${max_FO}${max_tr_arg};upsize,{D};dnsize,{D}"
} elseif {$sizing} {
    set abc_fine_tune       "upsize,{D};dnsize,{D}"
} else {
    set abc_fine_tune       ""
}

# set abc_script "read design.blif;fx;mfs;strash;${abc_rf};${abc_resyn2};${abc_retime_dly}; scleanup;${abc_map_old_dly};retime,-D,{D};&get,-n;&st;&dch;&nf;&put;${abc_fine_tune};stime,-p;print_stats -m;write output.blif"

set constr1 [open $::env(OBJECTS_DIR)/abc.script w]
puts $constr1 "fx;mfs;strash;${abc_rf};${abc_resyn2};${abc_retime_dly}; scleanup;${abc_map_old_dly};retime,-D,{D};&get,-n;&st;&dch;&nf;&put;${abc_fine_tune};stime,-p;print_stats -m"
close $constr1

set abc_script $::env(OBJECTS_DIR)/abc.script

# Technology mapping for cells
# ABC supports multiple liberty files, but the hook from Yosys to ABC doesn't
if {[info exist ::env(ABC_CLOCK_PERIOD_IN_PS)]} {
  puts "\[FLOW\] Set ABC_CLOCK_PERIOD_IN_PS to: $::env(ABC_CLOCK_PERIOD_IN_PS)"
  abc -D [expr $::env(ABC_CLOCK_PERIOD_IN_PS)] \
      -script $abc_script \
      -liberty $::env(DONT_USE_SC_LIB) \
      -constr $::env(OBJECTS_DIR)/abc.constr
} else {
  puts "\[WARN\]\[FLOW\] No clock period constraints detected in design"
  abc -liberty $::env(DONT_USE_SC_LIB) \
      -constr $::env(OBJECTS_DIR)/abc.constr
}

if {[catch {abc -D [expr $::env(ABC_CLOCK_PERIOD_IN_PS)] -script $abc_script -liberty $::env(DONT_USE_SC_LIB) -constr $::env(OBJECTS_DIR)/abc.constr} result]} {
    puts "\[ERROR\] ABC command failed: $result"
    exit 1
}

# Replace undef values with defined constants
setundef -zero

# Splitting nets resolves unwanted compound assign statements in netlist (assign {..} = {..})
splitnets

# Remove unused cells and wires
opt_clean -purge

# Technology mapping of constant hi- and/or lo-drivers
hilomap -singleton \
        -hicell {*}$::env(TIEHI_CELL_AND_PORT) \
        -locell {*}$::env(TIELO_CELL_AND_PORT)

# Insert buffer cells for pass through wires
insbuf -buf {*}$::env(MIN_BUF_CELL_AND_PORTS)

# Reports
tee -o $::env(REPORTS_DIR)/synth_check.txt check

# Create argument list for stat
set stat_libs ""
foreach lib $::env(DONT_USE_LIBS) {
  append stat_libs "-liberty $lib "
}
tee -o $::env(REPORTS_DIR)/synth_stat.txt stat {*}$stat_libs
tee -o $::env(REPORTS_DIR)/synth_stat.json stat -json {*}$stat_libs
tee -o $::env(REPORTS_DIR)/synth_check.txt check

# Write synthesized design
write_verilog -noattr -noexpr -nohex -nodec $::env(RESULTS_DIR)/1_1_yosys.v
