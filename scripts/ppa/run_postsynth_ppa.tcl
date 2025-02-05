source $::env(SCRIPTS_DIR)/load.tcl
load_design 1_synth.v 1_synth.sdc "Loaded synthesized design."

source $::env(SCRIPTS_DIR)/report_best_period.tcl
report_best_period "1_synth"

source $::env(SCRIPTS_DIR)/write_power_report.tcl
write_power_report "1_synth"

# Log sequential and combinational cell counts
set block [ord::get_db_block]
set seq_count 0
set comb_count 0

foreach inst [$block getInsts] {
	if { [[$inst getMaster] isSequential] == 1 } {
		set seq_count [expr $seq_count + 1]
	} else {
		set comb_count [expr $comb_count + 1]
	}
}

puts "Sequential Cells Count: $seq_count"
puts "Combinational Cells Count: $comb_count"

#report checks
tee -o $::env(REPORTS_DIR)/timing_report.txt sta -help