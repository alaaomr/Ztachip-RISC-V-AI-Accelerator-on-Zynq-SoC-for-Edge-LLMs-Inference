# =============================================================================
# run_step9_set_clock_rebuild.tcl
#   Set PS7 to 93.75 / 187.5 MHz (the clean exact-2x pair just below 100 MHz),
#   regenerate the block design, then rebuild the bitstream.
#
# WHY 93.75 / 187.5 (and NOT 90/180):
#   Zynq FCLKs = 1500 MHz IO-PLL divided by an INTEGER. 90 MHz needs 1500/16.667
#   (not an integer) so Vivado clamps it and breaks the mandatory
#   clk_x2 = 2 x clk_main rule -> garbage timing (we saw WNS = -4.48 ns).
#   93.75 = 1500/16 and 187.5 = 1500/8 are BOTH exact, ratio is exactly 2x,
#   and it sits just under 100 MHz for a small timing cushion.
#
# Editing zynq_ps_bd.tcl alone does NOT change an existing block design, so this
# script opens the live BD, sets the clocks, regenerates, and rebuilds.
#
# MEMORY NOTE: uses -jobs 2 (not 4). Routing this design peaks ~13 GB; with 4
#   parallel jobs on a 15 GB machine it exhausted RAM+swap and crashed. 2 jobs
#   is safe. Close other apps (browser etc.) before running for extra headroom.
#
# Run from the Vivado Tcl console:
#   source /home/eslam-elshokafy/Desktop/AIDAChip_Workshop_01/ztachip/HW/examples/ZC702/run_step9_set_clock_rebuild.tcl
#
# Takes ~45-60 min. Leave it running.
# =============================================================================

set ZC702 /home/eslam-elshokafy/Desktop/AIDAChip_Workshop_01/ztachip/HW/examples/ZC702

# Target clocks (MHz) - exact 2x pair from the 1500 MHz IO PLL
set FCLK0 93.75
set FCLK1 187.5

puts "INFO: ============================================================"
puts "INFO: Setting PS7 to $FCLK0 / $FCLK1 MHz and rebuilding bitstream"
puts "INFO: ============================================================"

# ---- Open project (safe if already open) -----------------------------------
catch {open_project $ZC702/ztachip_zc702.xpr}

# ---- Open the block design --------------------------------------------------
set bd [get_files zynq_system.bd]
puts "INFO: Opening block design: $bd"
open_bd_design $bd

# ---- Set the PS7 clocks -----------------------------------------------------
set ps [get_bd_cells -filter {VLNV =~ *processing_system7*}]
puts "INFO: PS7 cell = $ps"
set_property -dict [list \
   CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ $FCLK0 \
   CONFIG.PCW_FPGA1_PERIPHERAL_FREQMHZ $FCLK1 \
] $ps

# Read back the ACHIEVED values (Vivado reports what it can really make).
# These should be 93.75 and 187.5 exactly. If they differ, STOP and re-check.
set got0 [get_property CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ $ps]
set got1 [get_property CONFIG.PCW_FPGA1_PERIPHERAL_FREQMHZ $ps]
puts "INFO: FCLK0 requested $FCLK0 -> achieved $got0 MHz"
puts "INFO: FCLK1 requested $FCLK1 -> achieved $got1 MHz"
if {$got1 != [expr {2.0 * $got0}]} {
   puts "ERROR: FCLK1 is not exactly 2x FCLK0 (got $got0 / $got1)."
   puts "ERROR: This breaks ztachip's dual-pumped memories. ABORTING."
   return
}
puts "INFO: 2x clock relationship confirmed exact. Good."

# ---- Save and regenerate the BD --------------------------------------------
save_bd_design
puts "INFO: Regenerating block design output products..."
reset_target all [get_files zynq_system.bd]
generate_target all [get_files zynq_system.bd]
close_bd_design [current_bd_design]

# ---- Rebuild synthesis + implementation + bitstream ------------------------
puts "INFO: Resetting runs..."
reset_run synth_1
reset_run impl_1

puts "INFO: Running synthesis (~10-15 min)..."
launch_runs synth_1 -jobs 2
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
   puts "ERROR: Synthesis failed. Check the Messages tab."
   return
}

puts "INFO: Running implementation + bitstream (~30-40 min, -jobs 2 for memory safety)..."
launch_runs impl_1 -to_step write_bitstream -jobs 2
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
   puts "ERROR: Implementation failed. Check the Messages tab."
   return
}

# ---- Report final timing ----------------------------------------------------
open_run impl_1
puts "INFO: ============================================================"
puts "INFO: Final timing (WNS should be >= 0, or only a tiny negative):"
report_timing_summary -no_header -delay_type max -max_paths 1
puts "INFO: ============================================================"
puts "INFO: New $FCLK0 / $FCLK1 MHz bitstream:"
puts "INFO:   $ZC702/ztachip_zc702.runs/impl_1/main_zc702.bit"
puts "INFO: This matches config.vhd (93.75 MHz) and the firmware baud rate."
puts "INFO: ============================================================"
