# =============================================================================
# run_step5_fix_timing.tcl  — DEPRECATED. DO NOT USE.
# =============================================================================
# This early script set the clock to 100/200 MHz and also had a bug (it called
# set_property on a BD cell without open_bd_design first, so it never actually
# changed the generated block design).
#
# The project now targets 90/180 MHz for comfortable timing margin. To set the
# clock correctly and rebuild, use:
#
#   source /home/eslam-elshokafy/Desktop/AIDAChip_Workshop_01/ztachip/HW/examples/ZC702/run_step9_set_90mhz_rebuild.tcl
#
# That script opens the block design (required), sets FCLK0/FCLK1 to 90/180,
# regenerates the BD, and reruns synth + impl + bitstream.
# =============================================================================

puts "ERROR: run_step5_fix_timing.tcl is DEPRECATED."
puts "ERROR: Use run_step9_set_90mhz_rebuild.tcl instead (sets 90/180 MHz correctly)."
return
