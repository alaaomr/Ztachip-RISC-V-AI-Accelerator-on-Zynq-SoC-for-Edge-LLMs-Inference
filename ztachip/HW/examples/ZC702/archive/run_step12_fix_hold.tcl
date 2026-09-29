# =============================================================================
# run_step12_fix_hold.tcl
#   Fix the 3 HOLD violations on the clk_fpga_0 -> clk_fpga_1 dual-pump RAM
#   write paths (ztachip xregister_file DIBDI), WHS = -0.043 ns.
#
#   STRATEGY: enable POST-ROUTE phys_opt_design (which includes hold fixing) on
#   impl_1 and re-run. Hold is fixed by inserting REAL delay on the data paths
#   (they have setup headroom) -> silicon-correct, not a false_path band-aid.
#
#   SAFETY: backs up the current setup-OK bitstream BEFORE reset_run (which
#   deletes run outputs), so a bad re-run never leaves us with nothing.
#
#   MEMORY: -jobs 2 (routing peaks ~13GB on 15GB box). Close browser first.
#
# Run from the Vivado Tcl console:
#   source /home/eslam-elshokafy/Desktop/AIDAChip_Workshop_01/ztachip/HW/examples/ZC702/run_step12_fix_hold.tcl
# =============================================================================

set ZC702 /home/eslam-elshokafy/Desktop/AIDAChip_Workshop_01/ztachip/HW/examples/ZC702
set runbit $ZC702/ztachip_zc702.runs/impl_1/main_zc702.bit
set bakbit $ZC702/main_zc702_setupOK_holdfail.bit.bak

catch {open_project $ZC702/ztachip_zc702.xpr}

# ---- 1. Back up the current bitstream (good setup, bad hold) -----------------
if {[file exists $runbit]} {
   file copy -force $runbit $bakbit
   puts "INFO: Backed up current bitstream -> $bakbit"
} else {
   puts "INFO: No existing .bit to back up (will be created by this run)."
}

# ---- 2. Enable post-route physical optimization (does hold fixing) ----------
puts "INFO: Enabling post-route phys_opt (hold-fix) on impl_1..."
set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED true [get_runs impl_1]
set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.ARGS.DIRECTIVE Explore [get_runs impl_1]

# ---- 3. Clean re-run of implementation + bitstream --------------------------
puts "INFO: Resetting and re-running implementation (-jobs 2, ~30-45 min)..."
reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 2
wait_on_run impl_1

if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
   puts "ERROR: impl_1 did not reach 100%. Your backup is safe at:"
   puts "       $bakbit"
   puts "ERROR: Check Messages / runme.log."
   return
}

# ---- 4. Report BOTH setup and hold (full min_max) ---------------------------
open_run impl_1
puts "INFO: ============================================================"
puts "INFO:  FULL TIMING (setup AND hold) after hold-fix"
puts "INFO: ============================================================"
set wns [get_property STATS.WNS [get_runs impl_1]]
set whs [get_property STATS.WHS [get_runs impl_1]]
set tns [get_property STATS.TNS [get_runs impl_1]]
set ths [get_property STATS.THS [get_runs impl_1]]
puts "INFO:  Setup  WNS = $wns ns   (TNS = $tns)"
puts "INFO:  Hold   WHS = $whs ns   (THS = $ths)"

report_timing_summary -delay_type min_max -max_paths 1 -name timing_holdfix

# ---- 5. Verdict -------------------------------------------------------------
if {$wns >= 0 && $whs >= 0} {
   puts "INFO: ============================================================"
   puts "INFO:  SUCCESS — BOTH setup and hold MET. Board files are READY."
   puts "INFO:    .bit = $runbit"
   puts "INFO:  (backup of the old setup-only bitstream: $bakbit)"
   puts "INFO: ============================================================"
} else {
   puts "WARN: ============================================================"
   puts "WARN:  Still not fully met (WNS=$wns  WHS=$whs)."
   puts "WARN:  Do NOT program the board yet. Paste this output back."
   puts "WARN:  Next option would be a PL MMCM (Clocking Wizard) to generate"
   puts "WARN:  93.75 and 187.5 with matched skew (proper root-cause fix)."
   puts "WARN:  Your backup bitstream is at: $bakbit"
   puts "WARN: ============================================================"
}
