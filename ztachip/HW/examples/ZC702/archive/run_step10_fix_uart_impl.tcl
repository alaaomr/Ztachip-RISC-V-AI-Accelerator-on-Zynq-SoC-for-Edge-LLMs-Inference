# =============================================================================
# run_step10_fix_uart_impl.tcl
#   Re-run IMPLEMENTATION ONLY (no re-synthesis) after fixing the UART pin
#   constraints in main_zc702.xdc.
#
# CONTEXT:
#   The previous run routed fine at 93.75/187.5 MHz (0 failed nets) but
#   write_bitstream failed with DRC UCIO-1: UART_TXD had no pin LOC, because a
#   crash had reverted the XDC (UART pin lines were commented out).
#   main_zc702.xdc is now fixed: K18->UART_TXD, J18->UART_RXD (Bank 34, LVCMOS25).
#
#   Pin LOC/IOSTANDARD are IMPLEMENTATION constraints — they do NOT change the
#   synthesized netlist (which already contains the UART_TXD/UART_RXD ports).
#   So we only reset+rerun impl_1. ~25 min instead of ~45.
#
# MEMORY: -jobs 2 (routing peaks ~13GB on this 15GB box; reboot first if swap
#   is not empty). Close browser/other apps before running.
#
# Run from the Vivado Tcl console:
#   source /home/eslam-elshokafy/Desktop/AIDAChip_Workshop_01/ztachip/HW/examples/ZC702/run_step10_fix_uart_impl.tcl
# =============================================================================

set ZC702 /home/eslam-elshokafy/Desktop/AIDAChip_Workshop_01/ztachip/HW/examples/ZC702

puts "INFO: ============================================================"
puts "INFO: Re-running implementation only (UART pin fix, 93.75/187.5 MHz)"
puts "INFO: ============================================================"

catch {open_project $ZC702/ztachip_zc702.xpr}

# Make sure the edited XDC is the active constraints file and is re-read.
# (It is already in constrs_1; resetting impl forces a fresh constraint read.)
puts "INFO: Resetting implementation run..."
reset_run impl_1

puts "INFO: Launching implementation + bitstream (-jobs 2, ~25 min)..."
launch_runs impl_1 -to_step write_bitstream -jobs 2
wait_on_run impl_1

if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
   puts "ERROR: Implementation did not reach 100%. Check Messages / runme.log."
   puts "ERROR: If it says synth_1 is out of date, run:  reset_run synth_1; then"
   puts "       source run_step9_set_clock_rebuild.tcl  (full rebuild)."
   return
}

# ---- Confirm the bitstream really exists ------------------------------------
set bit $ZC702/ztachip_zc702.runs/impl_1/main_zc702.bit
if {[file exists $bit]} {
   puts "INFO: ============================================================"
   puts "INFO:  SUCCESS — bitstream generated:"
   puts "INFO:    $bit"
   puts "INFO: ============================================================"
} else {
   puts "ERROR: impl finished but no .bit found. Check write_bitstream step."
   return
}

# ---- Report the actual timing so we finally know the 93.75 MHz margin -------
open_run impl_1
puts "INFO: ---- TIMING SUMMARY (93.75 / 187.5 MHz) ----"
puts "INFO: WNS >= 0 means timing fully met. A tiny negative (> -0.1ns) is"
puts "INFO: acceptable on real silicon; a large negative needs attention."
report_timing_summary -no_header -delay_type max -max_paths 1

# ---- Confirm UART pins are placed where we expect ---------------------------
puts "INFO: ---- UART pin placement (should be K18 / J18) ----"
puts "INFO: UART_TXD -> [get_property PACKAGE_PIN [get_ports UART_TXD]]"
puts "INFO: UART_RXD -> [get_property PACKAGE_PIN [get_ports UART_RXD]]"
puts "INFO: ============================================================"
puts "INFO: If timing is met and pins are K18/J18, the board files are READY."
puts "INFO: ============================================================"
