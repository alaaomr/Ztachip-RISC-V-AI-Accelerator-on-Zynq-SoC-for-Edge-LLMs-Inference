# =============================================================================
# run_step14_timing_rerun.tcl
#   Close the last -10 ps of HOLD by re-running IMPLEMENTATION ONLY with
#   timing-focused directives. Synthesis (incl. the MMCM netlist) is already
#   valid and is NOT touched.
#
#   -10 ps is within normal place/route run-to-run variation, so a fresh,
#   timing-biased P&R has a good chance of reaching WHS >= 0. Directives used:
#     place_design               : ExtraTimingOpt
#     phys_opt_design            : Explore   (post-place)
#     route_design               : Explore   (more effort, better hold)
#     post-route phys_opt_design : Explore
#
#   SAFETY: backs up the current MMCM bitstream (setup-met, hold -10 ps) before
#   reset_run, so a worse re-run never loses the best result so far.
#
#   MEMORY: -jobs 2 (~50-70 min with these directives). Close browser first.
#
# Run from the Vivado Tcl console:
#   source /home/eslam-elshokafy/Desktop/AIDAChip_Workshop_01/ztachip/HW/examples/ZC702/run_step14_timing_rerun.tcl
# =============================================================================

set ZC702 /home/eslam-elshokafy/Desktop/AIDAChip_Workshop_01/ztachip/HW/examples/ZC702
set runbit $ZC702/ztachip_zc702.runs/impl_1/main_zc702.bit
set bakbit $ZC702/main_zc702_mmcm_hold10ps.bit.bak

catch {open_project $ZC702/ztachip_zc702.xpr}

# ---- 1. Back up the current MMCM bitstream (best so far) ---------------------
if {[file exists $runbit]} {
   file copy -force $runbit $bakbit
   puts "INFO: Backed up current MMCM bitstream (hold -10ps) -> $bakbit"
}

# ---- 2. Timing-focused implementation directives ----------------------------
puts "INFO: Setting timing-focused implementation directives..."
set_property STEPS.PLACE_DESIGN.ARGS.DIRECTIVE              ExtraTimingOpt [get_runs impl_1]
set_property STEPS.PHYS_OPT_DESIGN.IS_ENABLED              true           [get_runs impl_1]
set_property STEPS.PHYS_OPT_DESIGN.ARGS.DIRECTIVE          Explore        [get_runs impl_1]
set_property STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE             Explore        [get_runs impl_1]
set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED   true           [get_runs impl_1]
set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.ARGS.DIRECTIVE Explore      [get_runs impl_1]

# ---- 3. Re-run implementation only (synth stays valid) ----------------------
puts "INFO: Resetting implementation (synthesis kept) and re-running..."
reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 2
wait_on_run impl_1

if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
   puts "ERROR: impl_1 did not reach 100%. Best bitstream still safe: $bakbit"
   return
}

# ---- 4. Report setup + hold -------------------------------------------------
open_run impl_1
set wns [get_property STATS.WNS [get_runs impl_1]]
set whs [get_property STATS.WHS [get_runs impl_1]]
puts "INFO: ============================================================"
puts "INFO:  Setup  WNS = $wns ns"
puts "INFO:  Hold   WHS = $whs ns   (was -0.010 before this run)"
puts "INFO: ============================================================"
report_timing_summary -delay_type min_max -max_paths 1 -name timing_step14

# ---- 5. Verdict -------------------------------------------------------------
if {$wns >= 0 && $whs >= 0} {
   puts "INFO: ============================================================"
   puts "INFO:  SUCCESS — setup AND hold MET. Board files are READY (clean)."
   puts "INFO:    .bit = $runbit"
   puts "INFO: ============================================================"
} else {
   puts "WARN: ============================================================"
   puts "WARN:  Still WHS=$whs (WNS=$wns). Compare to -0.010 baseline:"
   puts "WARN:   - if BETTER but still <0: we're closing in; paste output."
   puts "WARN:   - if WORSE: restore the backup bitstream:"
   puts "WARN:       file copy -force $bakbit $runbit"
   puts "WARN:  Paste this output back either way."
   puts "WARN: ============================================================"
}
