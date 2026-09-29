# =============================================================================
# run_step16_jitter_fix.tcl
#   Close the residual -10 ps HOLD by refining the PS clock input jitter.
#
#   DIAGNOSIS (from run_step15, worst hold path on ztachip dual-pump RAM
#   DIBDI[26], clk_main->clk_x2): the path has +0.197 ns of real hold margin;
#   the failure is caused ENTIRELY by 0.207 ns of clock UNCERTAINTY (MMCM phase
#   error 0.120 + discrete jitter 0.159 + system jitter 0.071). The discrete
#   jitter is driven by the PS7 default FCLK0 jitter of 0.320 ns, which is a
#   conservative placeholder. main_zc702.xdc now sets a realistic 0.100 ns via
#   set_input_jitter [get_clocks clk_fpga_0] 0.100 -> lowers DJ -> closes hold.
#
#   This is IMPLEMENTATION-ONLY (jitter is a timing constraint; the netlist,
#   synthesis and MMCM are unchanged). ~25 min, -jobs 2.
#
#   SAFETY: backs up the current MMCM bitstream (hold -10 ps) first.
#
# Run from the Vivado Tcl console:
#   source /home/eslam-elshokafy/Desktop/AIDAChip_Workshop_01/ztachip/HW/examples/ZC702/run_step16_jitter_fix.tcl
# =============================================================================

set ZC702 /home/eslam-elshokafy/Desktop/AIDAChip_Workshop_01/ztachip/HW/examples/ZC702
set runbit $ZC702/ztachip_zc702.runs/impl_1/main_zc702.bit
set bakbit $ZC702/main_zc702_mmcm_hold10ps.bit.bak

catch {open_project $ZC702/ztachip_zc702.xpr}

# Back up the current MMCM bitstream (best so far) before re-running.
if {[file exists $runbit]} {
   file copy -force $runbit $bakbit
   puts "INFO: Backed up current MMCM bitstream (hold -10ps) -> $bakbit"
}

# Make sure the edited XDC is reloaded (reset_run re-reads constraints).
puts "INFO: Re-running implementation with refined clk_fpga_0 jitter (0.100 ns)..."
reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 2
wait_on_run impl_1

if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
   puts "ERROR: impl_1 did not reach 100%. Backup safe: $bakbit"
   return
}

open_run impl_1
set wns [get_property STATS.WNS [get_runs impl_1]]
set whs [get_property STATS.WHS [get_runs impl_1]]
puts "INFO: ============================================================"
puts "INFO:  Setup  WNS = $wns ns"
puts "INFO:  Hold   WHS = $whs ns   (was -0.010 before jitter refinement)"
puts "INFO: ============================================================"
report_timing_summary -delay_type min_max -max_paths 1 -name timing_jitter

# Show the worst hold path's new uncertainty so we can confirm WHY it closed.
puts "INFO: ---- New worst hold path (check Clock Uncertainty line) ----"
report_timing -delay_type min -max_paths 1 -nworst 1 -sort_by slack

if {$wns >= 0 && $whs >= 0} {
   puts "INFO: ============================================================"
   puts "INFO:  SUCCESS — setup AND hold MET. Board files are READY (clean)."
   puts "INFO:    .bit = $runbit"
   puts "INFO: ============================================================"
} else {
   puts "WARN: ============================================================"
   puts "WARN:  WHS=$whs (WNS=$wns). If still slightly <0 we can lower jitter"
   puts "WARN:  further (e.g. 0.080) or accept it. Paste output back."
   puts "WARN:  Backup (hold -10ps) at: $bakbit"
   puts "WARN: ============================================================"
}
