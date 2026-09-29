# =============================================================================
# run_step8_xsct_boot.tcl  — Level 5: Load firmware + model onto ZC702 via JTAG
#
# BEFORE running this script:
#   1. Connect the ZC702 JTAG USB cable to your PC
#   2. Power on the ZC702
#   3. In Vivado Hardware Manager, open the target and program the bitstream:
#         (the new one from run_step6: ztachip_zc702.runs/impl_1/main_zc702.bit)
#   4. Then open the Vivado Tcl console and run this script.
#
# Run from Vivado Tcl console:
#   source ~/Desktop/AIDAChip_Workshop_01/ztachip/HW/examples/ZC702/run_step8_xsct_boot.tcl
#
# What this does:
#   1. Connects to the Zynq ARM core via JTAG
#   2. Initializes the Zynq PS7 (DDR controller, clocks) using the auto-generated
#      ps7_init.tcl from our block design
#   3. Holds the VexRiscv in reset while loading (writes SLCR.FPGA_RST_CTRL)
#   4. Downloads SMOLLM2.ZUF (141MB) to DDR at 0x10000000
#   5. Downloads the RISC-V firmware ELF to DDR
#   6. Releases the VexRiscv from reset — chatbot starts running
#
# To see chatbot output: connect a USB-UART adapter to ZC702 UART pins and
# open a terminal at 115200 baud (8N1).
# =============================================================================

set ZTACHIP /home/eslam-elshokafy/Desktop/AIDAChip_Workshop_01/ztachip
set ZC702   $ZTACHIP/HW/examples/ZC702
set PS7INIT $ZC702/ztachip_zc702.gen/sources_1/bd/zynq_system/ip/zynq_system_processing_system7_0_0/ps7_init.tcl
set ZUF     $ZTACHIP/models/SMOLLM2.ZUF
# Firmware is loaded as a FLAT BINARY (not the ELF). The XSCT target is the ARM
# core; loading a RISC-V ELF onto an ARM target can fail on arch mismatch and
# would point the ARM PC at RISC-V code. Loading the .bin as raw data into DDR
# avoids both problems — the VexRiscv boots from this DDR image on reset release.
set BIN     $ZTACHIP/SW/build/ztachip.bin

# Firmware load address = VexRiscv reset vector = start of DDR image
set FW_DDR_ADDR  0x00004000
# ZUF load address in DDR (256 MB mark — well above the RISC-V heap (~198 MB))
set ZUF_DDR_ADDR 0x10000000

# Zynq SLCR registers for VexRiscv reset control
set SLCR_UNLOCK     0xF8000008
set FPGA_RST_CTRL   0xF8000240

puts "INFO: ============================================================"
puts "INFO: ZC702 JTAG Boot Loader — Level 5"
puts "INFO: ============================================================"

# ---- Sanity checks ----------------------------------------------------------
foreach f [list $PS7INIT $ZUF $BIN] {
    if {![file exists $f]} {
        puts "ERROR: File not found: $f"
        return
    }
}
puts "INFO: All files found. Starting..."

# ---- Step 1: Connect to ARM core 0 -----------------------------------------
puts "INFO: Connecting to Zynq ARM core via JTAG..."
connect
after 500
targets -set -filter {name =~ "ARM Cortex-A9 MPCore #0"}
puts "INFO: Connected."

# ---- Step 2: Initialize PS7 (DDR, clocks) ----------------------------------
puts "INFO: Initializing Zynq PS7 (DDR controller)..."
source $PS7INIT
ps7_init
ps7_post_config
puts "INFO: PS7 initialized — DDR is now accessible."

# ---- Step 3: Hold VexRiscv in reset -----------------------------------------
# SLCR_UNLOCK allows writing to SLCR registers.
# FPGA_RST_CTRL bit 0 = 1 → FPGA0 reset asserted → VexRiscv held in reset.
mwr $SLCR_UNLOCK   0x0000DF0D
mwr $FPGA_RST_CTRL 0x00000001
puts "INFO: VexRiscv held in reset. Loading data..."

# ---- Step 4: Download SMOLLM2.ZUF to DDR at 0x10000000 --------------------
set zuf_size [file size $ZUF]
puts "INFO: Downloading SMOLLM2.ZUF ([expr {$zuf_size / 1024 / 1024}] MB) to DDR..."
puts "INFO: This may take 1-2 minutes over JTAG..."
dow -data $ZUF $ZUF_DDR_ADDR
puts "INFO: Model loaded to DDR at $ZUF_DDR_ADDR."

# ---- Step 5: Download RISC-V firmware (flat binary) into DDR ---------------
set bin_size [file size $BIN]
puts "INFO: Downloading firmware ([expr {$bin_size / 1024 / 1024}] MB) to DDR at $FW_DDR_ADDR..."
dow -data $BIN $FW_DDR_ADDR
puts "INFO: Firmware loaded."

# ---- Step 6: Release VexRiscv from reset → chatbot starts ------------------
mwr $FPGA_RST_CTRL 0x00000000
puts ""
puts "INFO: ============================================================"
puts "INFO:  VexRiscv released from reset — chatbot is starting!"
puts "INFO: ============================================================"
puts "INFO: Connect a USB-UART adapter to the ZC702 PL UART pins (Bank 34, 2.5V):"
puts "INFO:   ZC702 K18 (UART_TXD)  -> adapter RX"
puts "INFO:   ZC702 J18 (UART_RXD)  <- adapter TX"
puts "INFO:   adapter GND           -> ZC702 GND"
puts "INFO:   Baud: 115200, 8N1.  Adapter MUST be 2.5V-tolerant."
puts "INFO: Open a terminal (e.g., minicom or screen) to see output."
puts "INFO: ============================================================"
