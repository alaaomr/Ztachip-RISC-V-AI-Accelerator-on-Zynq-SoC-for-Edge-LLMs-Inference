# =============================================================================
# board_bringup_test.tcl  — Board-day STEP 1: foundation test (run in xsct)
#
# Proves three things before we build anything else:
#   1. The Platform Cable USB II can talk to the Zynq over JTAG
#   2. The FPGA programs (our timing-clean bitstream loads)
#   3. We can READ and WRITE DDR over JTAG  <-- this is what the console needs
#
# Run from a terminal:
#   source /home/eslam-elshokafy/Xilinx/2025.2/Vitis/settings64.sh
#   xsct /home/eslam-elshokafy/Desktop/AIDAChip_Workshop_01/ztachip/HW/examples/ZC702/board_bringup_test.tcl
# =============================================================================

set ZTACHIP /home/eslam-elshokafy/Desktop/AIDAChip_Workshop_01/ztachip
set ZC702   $ZTACHIP/HW/examples/ZC702
set PS7INIT $ZC702/ztachip_zc702.gen/sources_1/bd/zynq_system/ip/zynq_system_processing_system7_0_0/ps7_init.tcl
set BIT     $ZC702/ztachip_zc702.runs/impl_1/main_zc702.bit

# Test address: 512 MB into DDR, safely above firmware (<256MB) and model (ends 397MB)
set TEST_ADDR 0x20000000

puts "INFO: ============================================================"
puts "INFO: ZC702 BOARD-DAY FOUNDATION TEST"
puts "INFO: ============================================================"

foreach f [list $PS7INIT $BIT] {
    if {![file exists $f]} { puts "ERROR: missing $f"; return }
}

# ---- 1. Connect over JTAG (Platform Cable USB II) --------------------------
puts "INFO: \[1/4\] Connecting to Zynq via JTAG..."
connect
after 500
# Show what the cable sees (you should see the Zynq ARM cores + the FPGA)
puts "INFO: JTAG targets visible:"
targets

# ---- 2. Init PS7 (clocks incl FCLK0 that feeds our PL MMCM, + DDR) ---------
puts "INFO: \[2/4\] Initializing PS7 (clocks + DDR controller)..."
targets -set -filter {name =~ "ARM Cortex-A9 MPCore #0"}
rst -processor
source $PS7INIT
ps7_init
ps7_post_config
puts "INFO: PS7 up -> FCLK0 running, DDR accessible."

# ---- 3. Program the FPGA (our timing-clean bitstream) ---------------------
puts "INFO: \[3/4\] Programming FPGA with main_zc702.bit..."
targets -set -filter {name =~ "xc7z020"}
fpga -file $BIT
puts "INFO: FPGA programmed (DONE should be high)."

# ---- 4. DDR read/write test over JTAG (the console's foundation) ----------
puts "INFO: \[4/4\] Testing DDR read/write at $TEST_ADDR over JTAG..."
targets -set -filter {name =~ "ARM Cortex-A9 MPCore #0"}
set pattern 0xDEADBEEF
mwr $TEST_ADDR $pattern
set readback [lindex [mrd -value $TEST_ADDR] 0]
puts "INFO:   wrote    $pattern"
puts "INFO:   read back 0x[format %08X $readback]"
if {$readback == $pattern} {
    # second pattern to be sure it's real RAM, not a stuck bus
    mwr $TEST_ADDR 0x12345678
    set rb2 [lindex [mrd -value $TEST_ADDR] 0]
    if {$rb2 == 0x12345678} {
        puts "INFO: ============================================================"
        puts "INFO:  PASS - DDR read/write over JTAG WORKS."
        puts "INFO:  The JTAG-DDR console approach is confirmed viable."
        puts "INFO: ============================================================"
    } else {
        puts "WARN: second pattern mismatch (got 0x[format %08X $rb2]) - investigate"
    }
} else {
    puts "ERROR: DDR readback FAILED. PS7 init or DDR may not be up."
    puts "ERROR: Do NOT proceed to the console until this passes."
}
