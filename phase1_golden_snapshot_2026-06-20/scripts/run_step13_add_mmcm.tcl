# =============================================================================
# run_step13_add_mmcm.tcl
#   PROPER ROOT-CAUSE FIX for the 3 hold violations (clk_fpga_0 -> clk_fpga_1).
#
#   Creates a Clocking Wizard (MMCM) IP named "clk_mmcm" that generates BOTH
#   clk_main (93.75 MHz) and clk_x2_main (187.5 MHz) from ONE source (PS FCLK0).
#   main_zc702.v has already been edited to instantiate it and feed soc_base
#   from the MMCM outputs (clk_x2 no longer comes from a separate PS FCLK).
#
#   WHY THIS FIXES HOLD: both clocks now share the MMCM as a common root, so
#   Vivado applies clock pessimism removal on the cross-clock paths instead of
#   full worst-case pessimism. This is how the original ztachip (Arty) did it.
#
#   MEMORY: full rebuild (synth + impl), -jobs 2. Close browser first.
#   SAFETY: the setup-OK backup bitstream from step12 still exists:
#           main_zc702_setupOK_holdfail.bit.bak
#
# Run from the Vivado Tcl console:
#   source /home/eslam-elshokafy/Desktop/AIDAChip_Workshop_01/ztachip/HW/examples/ZC702/run_step13_add_mmcm.tcl
# =============================================================================

set ZC702 /home/eslam-elshokafy/Desktop/AIDAChip_Workshop_01/ztachip/HW/examples/ZC702
catch {open_project $ZC702/ztachip_zc702.xpr}

# ---- 1. (Re)create the MMCM IP ---------------------------------------------
# If a previous attempt left clk_mmcm, remove it so we start clean.
if {[llength [get_ips -quiet clk_mmcm]] > 0} {
   puts "INFO: Removing existing clk_mmcm IP to recreate it cleanly..."
   export_ip_user_files -of_objects [get_ips clk_mmcm] -no_script -reset -force -quiet
   remove_files [get_files -quiet *clk_mmcm.xci]
}

puts "INFO: Creating Clocking Wizard (MMCM) IP 'clk_mmcm'..."
create_ip -name clk_wiz -vendor xilinx.com -library ip -module_name clk_mmcm

set_property -dict [list \
  CONFIG.PRIMITIVE                {MMCM} \
  CONFIG.PRIM_SOURCE              {Global_buffer} \
  CONFIG.PRIM_IN_FREQ            {93.75} \
  CONFIG.CLKIN1_JITTER_PS        {106.67} \
  CONFIG.NUM_OUT_CLKS            {2} \
  CONFIG.CLKOUT1_USED            {true} \
  CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {93.75} \
  CONFIG.CLKOUT2_USED            {true} \
  CONFIG.CLKOUT2_REQUESTED_OUT_FREQ {187.5} \
  CONFIG.USE_LOCKED              {true} \
  CONFIG.USE_RESET               {true} \
  CONFIG.RESET_TYPE              {ACTIVE_LOW} \
  CONFIG.RESET_PORT              {resetn} \
  CONFIG.CLK_IN1_BOARD_INTERFACE {Custom} \
  CONFIG.RESET_BOARD_INTERFACE   {Custom} \
] [get_ips clk_mmcm]

puts "INFO: Generating IP targets (this also reports the ACTUAL output freqs)..."
generate_target all [get_ips clk_mmcm]
catch {synth_ip [get_ips clk_mmcm]}

# Report what the MMCM actually produced (should be 93.750 and 187.500).
puts "INFO: clk_out1 actual = [get_property CONFIG.MMCM_CLKOUT0_DIVIDE_F [get_ips clk_mmcm]] (divide)"
puts "INFO: clk_out2 actual = [get_property CONFIG.MMCM_CLKOUT1_DIVIDE   [get_ips clk_mmcm]] (divide)"
puts "INFO: VCO MULT/DIV     = [get_property CONFIG.MMCM_CLKFBOUT_MULT_F [get_ips clk_mmcm]] / [get_property CONFIG.MMCM_DIVCLK_DIVIDE [get_ips clk_mmcm]]"

update_compile_order -fileset sources_1

# ---- 2. Full rebuild (Verilog + new IP changed the netlist) -----------------
puts "INFO: Resetting synthesis and implementation for a full clean rebuild..."
reset_run impl_1
reset_run synth_1

puts "INFO: Launching synth + impl + bitstream (-jobs 2, ~40-50 min)..."
launch_runs impl_1 -to_step write_bitstream -jobs 2
wait_on_run impl_1

if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
   puts "ERROR: Run did not reach 100%. Check Messages / runme.log."
   puts "ERROR: Backup bitstream still safe: $ZC702/main_zc702_setupOK_holdfail.bit.bak"
   return
}

# ---- 3. Report BOTH setup and hold -----------------------------------------
open_run impl_1
set wns [get_property STATS.WNS [get_runs impl_1]]
set whs [get_property STATS.WHS [get_runs impl_1]]
puts "INFO: ============================================================"
puts "INFO:  Setup  WNS = $wns ns"
puts "INFO:  Hold   WHS = $whs ns"
puts "INFO: ============================================================"
report_timing_summary -delay_type min_max -max_paths 1 -name timing_mmcm

# Confirm the two clocks now share the MMCM and are exactly 2x.
puts "INFO: ---- Clocks (clk_main and clk_x2_main should be 93.75 / 187.5) ----"
report_clocks

# UART pins sanity.
puts "INFO: UART_TXD -> [get_property PACKAGE_PIN [get_ports UART_TXD]]"
puts "INFO: UART_RXD -> [get_property PACKAGE_PIN [get_ports UART_RXD]]"

# ---- 4. Verdict -------------------------------------------------------------
if {$wns >= 0 && $whs >= 0} {
   puts "INFO: ============================================================"
   puts "INFO:  SUCCESS — setup AND hold MET. Board files are READY."
   puts "INFO:    .bit = $ZC702/ztachip_zc702.runs/impl_1/main_zc702.bit"
   puts "INFO: ============================================================"
} else {
   puts "WARN: ============================================================"
   puts "WARN:  Still not fully met (WNS=$wns  WHS=$whs). Paste output back."
   puts "WARN: ============================================================"
}
