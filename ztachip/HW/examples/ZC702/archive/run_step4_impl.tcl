# Step 4: Run Implementation + Bitstream for ztachip ZC702
# This does: Place, Route, Timing check, then Generate Bitstream
#
# Run from Vivado Tcl console:
#   source ~/Desktop/AIDAChip_Workshop_01/ztachip/HW/examples/ZC702/run_step4_impl.tcl
#
# Expected time: 15-30 minutes

puts "INFO: ============================================================"
puts "INFO: Step 4 - Implementation + Bitstream Generation"
puts "INFO: Expected time: 15-30 minutes"
puts "INFO: ============================================================"

# Run full implementation all the way to bitstream in one command
puts "INFO: Launching implementation (place + route + bitstream)..."
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

# Check results
set impl_status   [get_property STATUS   [get_runs impl_1]]
set impl_progress [get_property PROGRESS [get_runs impl_1]]
puts "INFO: Implementation status   = $impl_status"
puts "INFO: Implementation progress = $impl_progress"

if {$impl_progress eq "100%"} {
    puts "INFO: Implementation PASSED. Checking timing..."
    open_run impl_1 -name impl_1

    # Report timing - most important check
    puts "INFO: ============================================================"
    puts "INFO: TIMING SUMMARY (WNS must be >= 0 to be correct)"
    puts "INFO: WNS = Worst Negative Slack"
    puts "INFO:   WNS >= 0  : PASS - all signals arrive on time"
    puts "INFO:   WNS <  0  : FAIL - timing violation, need to fix"
    puts "INFO: ============================================================"
    report_timing_summary -quiet -max_paths 5

    # Report final utilization (more accurate than synthesis estimate)
    puts "INFO: ============================================================"
    puts "INFO: FINAL UTILIZATION (after place & route)"
    puts "INFO: ============================================================"
    report_utilization -quiet

    puts "INFO: ============================================================"
    puts "INFO: Bitstream location:"
    puts "INFO:   ztachip_zc702.runs/impl_1/main_zc702.bit"
    puts "INFO: ============================================================"
} else {
    puts "ERROR: Implementation did not complete."
    puts "ERROR: Check the Messages tab in Vivado GUI for errors."
}
