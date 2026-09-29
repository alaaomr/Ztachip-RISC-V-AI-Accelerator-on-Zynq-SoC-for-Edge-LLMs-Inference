# =============================================================================
# run_pmu_bitstream.tcl
#   Rebuild the bitstream WITH the new PMU, SAFELY reusing the existing project
#   so the clk_mmcm IP + jitter constraint (the timing closure) are preserved.
#
#   It: opens the project, adds pmu.vhd (the only new file), forces re-synthesis
#   (soc_base.vhd / ztachip_pkg.vhd were edited), runs impl + write_bitstream,
#   and reports whether timing still closes.
#
#   Run via:  bash run_pmu_bitstream.sh   (no board needed)
# =============================================================================
set ZC702 /home/eslam-elshokafy/Desktop/AIDAChip_Workshop_01/ztachip/HW/examples/ZC702
set RTL   /home/eslam-elshokafy/Desktop/AIDAChip_Workshop_01/ztachip/HW/src
set JOBS  2

puts "INFO: opening existing project (keeps MMCM + jitter)..."
open_project $ZC702/ztachip_zc702.xpr

# --- add the new PMU peripheral if not already a source ---------------------
set pmu $RTL/soc/peripherals/pmu.vhd
if {[llength [get_files -quiet *pmu.vhd]] == 0} {
   puts "INFO: adding pmu.vhd to the project..."
   add_files -norecurse $pmu
} else {
   puts "INFO: pmu.vhd already in project."
}
update_compile_order -fileset sources_1

# --- force re-synthesis (edited soc_base.vhd + ztachip_pkg.vhd) -------------
puts "INFO: resetting + launching synthesis (-jobs $JOBS)..."
reset_run synth_1
launch_runs synth_1 -jobs $JOBS
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
   puts "ERROR: synthesis did not finish. Check the synth_1 log."
   return
}

# --- implementation + bitstream --------------------------------------------
# The base design closes at ~zero margin; the GUI build that closed timing used
# the Performance_ExplorePostRoutePhysOpt strategy (and NO global fanout limit,
# since the worst path is the TCM clk_x2->clk_main crossing, not a fanout path).
# Reproduce that here so the batch build also closes.
catch {reset_run impl_1}
catch {reset_property STEPS.SYNTH_DESIGN.ARGS.FANOUT_LIMIT [get_runs synth_1]}
catch {set_property strategy Performance_ExplorePostRoutePhysOpt [get_runs impl_1]}
puts "INFO: impl strategy = [get_property strategy [get_runs impl_1]]"
puts "INFO: launching implementation + write_bitstream..."
launch_runs impl_1 -to_step write_bitstream -jobs $JOBS
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
   puts "ERROR: implementation/bitstream did not finish. Check the impl_1 log."
   return
}

# --- timing check (the thing to verify) ------------------------------------
open_run impl_1
set wns [get_property STATS.WNS [get_runs impl_1]]
set whs [get_property STATS.WHS [get_runs impl_1]]
puts "INFO: ============================================================"
puts "INFO:  TIMING   WNS = $wns ns    WHS = $whs ns"
if {$wns >= 0 && $whs >= 0} {
   puts "INFO:  >>> TIMING CLOSED - bitstream is GOOD with the PMU <<<"
} else {
   puts "INFO:  *** TIMING VIOLATION - do NOT use on board; tell Claude ***"
}
puts "INFO:  bitstream: $ZC702/ztachip_zc702.runs/impl_1/main_zc702.bit"
puts "INFO:  (golden backup safe at phase1_golden_snapshot_2026-06-20/bitstream/)"
puts "INFO: ============================================================"
