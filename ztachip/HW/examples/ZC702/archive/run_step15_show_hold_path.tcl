# =============================================================================
# run_step15_show_hold_path.tcl
#   DIAGNOSTIC ONLY (changes nothing). Shows the single worst HOLD path in full
#   detail so we understand the residual -10 ps before re-running implementation.
#   Uses the design already open from step13 (open_run impl_1).
#
# Run from the Vivado Tcl console:
#   source /home/eslam-elshokafy/Desktop/AIDAChip_Workshop_01/ztachip/HW/examples/ZC702/run_step15_show_hold_path.tcl
# =============================================================================

set ZC702 /home/eslam-elshokafy/Desktop/AIDAChip_Workshop_01/ztachip/HW/examples/ZC702

# Make sure a routed design is open; open impl_1 if not.
if {[catch {get_property TOP [current_design]}]} {
   catch {open_project $ZC702/ztachip_zc702.xpr}
   open_run impl_1
}

puts "INFO: ============================================================"
puts "INFO:  WORST HOLD PATH (full detail)"
puts "INFO: ============================================================"
report_timing -delay_type min -max_paths 1 -nworst 1 -sort_by slack -input_pins

puts "INFO: ============================================================"
puts "INFO:  TOP 5 HOLD endpoints (compact: slack + clock domains)"
puts "INFO: ============================================================"
set paths [get_timing_paths -delay_type min -max_paths 5 -nworst 5 -sort_by slack]
foreach p $paths {
   set slack [get_property SLACK $p]
   set sc    [get_property STARTPOINT_CLOCK $p]
   set ec    [get_property ENDPOINT_CLOCK   $p]
   set sp    [get_property STARTPOINT_PIN $p]
   set ep    [get_property ENDPOINT_PIN   $p]
   set tag "OK  "
   if {$slack < 0} { set tag "FAIL" }
   puts "$tag slack=$slack  from($sc) -> to($ec)"
   puts "       start: $sp"
   puts "       end  : $ep"
}
puts "INFO: ============================================================"
puts "INFO: Same-clock (e.g. clk_out1->clk_out1) = intra-clock hold, easy P&R fix."
puts "INFO: clk_out1<->clk_out2 = the dual-pump 2x crossing (jitter-limited)."
puts "INFO: ============================================================"
