# =============================================================================
# run_pmu_build_gui.tcl
#   Source this in the Tcl Console when the project is ALREADY OPEN in the GUI.
#   (It does NOT open_project.) It clears the interrupted synth_1 run, then runs
#   synthesis -> implementation -> bitstream and reports timing.
#
#   In the Tcl Console:
#     source /home/eslam-elshokafy/Desktop/AIDAChip_Workshop_01/ztachip/HW/examples/ZC702/run_pmu_build_gui.tcl
# =============================================================================
set ZC702 /home/eslam-elshokafy/Desktop/AIDAChip_Workshop_01/ztachip/HW/examples/ZC702
set JOBS  2

puts "INFO: clearing any interrupted runs..."
catch {reset_run impl_1}
catch {reset_run synth_1}
# Undo any leftover fanout_limit (the failing path is the TCM cross-clock path,
# not a fanout path, so global replication is not the right lever here).
catch {reset_property STEPS.SYNTH_DESIGN.ARGS.FANOUT_LIMIT [get_runs synth_1]}
# Timing-driven implementation (this brought hold to +0.031 ns last run).
catch {set_property strategy Performance_ExplorePostRoutePhysOpt [get_runs impl_1]}
puts "INFO: impl strategy = [get_property strategy [get_runs impl_1]]"
puts "INFO: synth_1 status = [get_property STATUS [get_runs synth_1]]"

puts "INFO: launching synthesis (-jobs $JOBS)..."
launch_runs synth_1 -jobs $JOBS
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
   puts "ERROR: synthesis did not finish (status [get_property STATUS [get_runs synth_1]])."
   return
}

puts "INFO: launching implementation + write_bitstream..."
launch_runs impl_1 -to_step write_bitstream -jobs $JOBS
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
   puts "ERROR: implementation/bitstream did not finish."
   return
}

open_run impl_1
set wns [get_property STATS.WNS [get_runs impl_1]]
set whs [get_property STATS.WHS [get_runs impl_1]]
puts "============================================================"
puts " TIMING   WNS = $wns ns    WHS = $whs ns"
if {$wns >= 0 && $whs >= 0} {
   puts " >>> TIMING CLOSED - bitstream is GOOD with the PMU <<<"
} else {
   puts " *** TIMING VIOLATION - tell Claude the WNS/WHS numbers ***"
}
puts " bitstream: $ZC702/ztachip_zc702.runs/impl_1/main_zc702.bit"
puts "============================================================"
