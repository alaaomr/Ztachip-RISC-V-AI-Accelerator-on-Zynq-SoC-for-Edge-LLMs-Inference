# Step 3: Run synthesis for ztachip ZC702 project
# Run this from Vivado Tcl console after project is open.
# If project is not open, uncomment the open_project line below.
#
# open_project /home/eslam-elshokafy/Desktop/AIDAChip_Workshop_01/ztachip/HW/examples/ZC702/ztachip_zc702.xpr

puts "INFO: Launching synthesis (synth_1) with 4 jobs..."
launch_runs synth_1 -jobs 4
wait_on_run synth_1

set synth_status [get_property STATUS [get_runs synth_1]]
set synth_progress [get_property PROGRESS [get_runs synth_1]]
puts "INFO: Synthesis status   = $synth_status"
puts "INFO: Synthesis progress = $synth_progress"

if {$synth_progress eq "100%"} {
    puts "INFO: Synthesis PASSED. Opening run to report utilization..."
    open_run synth_1 -name synth_1
    report_utilization -file utilization_synth.rpt -quiet
    puts "INFO: ============================================================"
    puts "INFO: Utilization report saved to: utilization_synth.rpt"
    puts "INFO: Key check: LUT usage must be < 53200 (XC7Z020 limit)"
    puts "INFO: ============================================================"
    report_utilization
} else {
    puts "ERROR: Synthesis did not complete successfully."
    puts "ERROR: Check Messages tab in Vivado GUI for errors."
}
