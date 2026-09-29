# =============================================================================
# run_step11_report_hold.tcl
#   DIAGNOSTIC ONLY — does not change anything.
#   The full min_max timing report shows 3 HOLD violations (WHS -0.043 ns) even
#   though SETUP is met (WNS 0.000). Hold is NOT fixed by changing clock speed.
#   This script prints the exact failing hold paths so we can choose the fix.
#
# Run from the Vivado Tcl console:
#   source /home/eslam-elshokafy/Desktop/AIDAChip_Workshop_01/ztachip/HW/examples/ZC702/run_step11_report_hold.tcl
# =============================================================================

set ZC702 /home/eslam-elshokafy/Desktop/AIDAChip_Workshop_01/ztachip/HW/examples/ZC702

# The implementation run is usually already open from step10. Open it if not.
if {[catch {get_property TOP [current_design]}]} {
   catch {open_project $ZC702/ztachip_zc702.xpr}
   open_run impl_1
}

puts "INFO: ============================================================"
puts "INFO:  WORST 10 HOLD (MIN-DELAY) PATHS"
puts "INFO:  Look at the 'From Clock' / 'To Clock' lines of each path."
puts "INFO:  If they cross clk_fpga_0 <-> clk_fpga_1, it's the CDC; if both"
puts "INFO:  clocks are the SAME, it's an intra-clock hold the router left."
puts "INFO: ============================================================"
report_timing -delay_type min -max_paths 10 -nworst 10 -sort_by slack \
   -input_pins -name hold_paths_1

# Compact text summary of just the failing hold endpoints + their clocks.
puts "INFO: ---- Per-path hold slack and clock domains ----"
set paths [get_timing_paths -delay_type min -max_paths 10 -nworst 10 -sort_by slack]
foreach p $paths {
   set slack [get_property SLACK $p]
   set sc    [get_property STARTPOINT_CLOCK $p]
   set ec    [get_property ENDPOINT_CLOCK   $p]
   set sp    [get_property STARTPOINT_PIN $p]
   set ep    [get_property ENDPOINT_PIN   $p]
   if {$slack < 0} {
      puts "FAIL  slack=$slack  from($sc) -> to($ec)"
      puts "        start: $sp"
      puts "        end  : $ep"
   }
}
puts "INFO: ============================================================"
puts "INFO: Paste this output back. Then we pick the correct fix:"
puts "INFO:  - CDC clk0<->clk1 hold  -> set_clock_groups / proper CDC constraint"
puts "INFO:  - intra-clock hold      -> phys_opt_design -hold_fix and re-route"
puts "INFO: ============================================================"
