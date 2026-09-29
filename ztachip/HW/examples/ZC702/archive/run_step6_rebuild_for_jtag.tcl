# =============================================================================
# run_step6_rebuild_for_jtag.tcl  — Level 5: Rebuild bitstream with sim VexRiscv
#
# WHY: The original bitstream uses riscv/xilinx_jtag/riscv.v which starts at
#      address 0x00000000 (TCM BRAM — starts all zeros, so the CPU hangs).
#      The sim VexRiscv (riscv/sim/riscv.vhd) starts at 0x00004000 (DDR),
#      which is where XSCT loads the firmware. Same AXI ports, no TCM needed.
#
# Run from Vivado Tcl console:
#   source ~/Desktop/AIDAChip_Workshop_01/ztachip/HW/examples/ZC702/run_step6_rebuild_for_jtag.tcl
#
# This takes ~45 minutes. After it finishes, the new .bit is ready to flash.
# =============================================================================

set ZTACHIP /home/eslam-elshokafy/Desktop/AIDAChip_Workshop_01/ztachip
set ZC702   $ZTACHIP/HW/examples/ZC702

puts "INFO: ============================================================"
puts "INFO: Level 5 — Rebuilding bitstream with sim VexRiscv"
puts "INFO: (starts at 0x00004000 = DDR, no TCM initialization needed)"
puts "INFO: ============================================================"

# Open project
catch {open_project $ZC702/ztachip_zc702.xpr}

# --- Swap the VexRiscv source -------------------------------------------------
# Remove the xilinx_jtag riscv.v (starts at 0x00000000 = TCM)
set jtag_riscv "$ZTACHIP/HW/riscv/xilinx_jtag/riscv.v"
set sim_riscv  "$ZTACHIP/HW/riscv/sim/riscv.vhd"

puts "INFO: Removing xilinx_jtag riscv.v ..."
catch {remove_files $jtag_riscv}

puts "INFO: Adding sim riscv.vhd (reset vector = 0x00004000) ..."
add_files -norecurse $sim_riscv

# Mark it as belonging to synthesis fileset (not just sim)
set_property file_type {VHDL} [get_files $sim_riscv]

puts "INFO: VexRiscv swapped. Updating compile order..."
update_compile_order -fileset sources_1

# --- Re-run synthesis, implementation, bitstream ----------------------------
puts "INFO: Resetting runs (sources changed)..."
reset_run synth_1
reset_run impl_1

puts "INFO: Starting synthesis (this takes ~15 min)..."
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    puts "ERROR: Synthesis failed."
    return
}
puts "INFO: Synthesis done."

puts "INFO: Starting implementation (this takes ~20 min)..."
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    puts "ERROR: Implementation failed."
    return
}

puts ""
puts "INFO: ============================================================"
puts "INFO: DONE! New bitstream:"
puts "INFO:   $ZC702/ztachip_zc702.runs/impl_1/main_zc702.bit"
puts "INFO: ============================================================"
puts "INFO: Next: build the board firmware, then run the XSCT loader."
puts "INFO:   bash $ZC702/run_step7_build_firmware.sh"
