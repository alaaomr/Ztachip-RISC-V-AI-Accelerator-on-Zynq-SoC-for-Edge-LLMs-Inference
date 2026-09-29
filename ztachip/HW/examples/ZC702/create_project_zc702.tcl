#------------------------------------------------------------------------------
# create_project_zc702.tcl
# Vivado project creation script for ztachip on Zynq ZC702
#
# HOW TO RUN (from Vivado Tcl console OR Vivado -mode tcl):
#   cd <ztachip_root>/HW/examples/ZC702
#   source create_project_zc702.tcl -notrace
#
# PREREQUISITES:
#   1. Vivado 2020.1 or newer installed
#   2. ZC702 board files installed in Vivado
#      (Help > Manage Boards in Vivado, search "ZC702" and install)
#   3. ztachip RTL source tree at ../../src relative to this script
#   4. config.vhd must have exmem_data_width_c = 64 (already done in Step 1)
#
# WHAT THIS SCRIPT DOES:
#   1. Creates a new Vivado project targeting XC7Z020CLG484-1
#   2. Adds all ztachip RTL (VHDL + Verilog)
#   3. Creates the Zynq PS block design (zynq_system.bd)
#   4. Generates the BD wrapper (zynq_system_wrapper.v)
#   5. Creates FP32 floating point IP instances
#   6. Adds XDC constraints
#   7. Sets main_zc702.v as the top module
#
# AFTER THIS SCRIPT:
#   - Run synthesis: launch_runs synth_1 -jobs 4
#   - Run implementation: launch_runs impl_1 -to_step write_bitstream -jobs 4
#   - Program: use XSCT or Vivado Hardware Manager
#------------------------------------------------------------------------------

set script_dir [file dirname [file normalize [info script]]]
set rtl_dir    [file normalize "$script_dir/../../src"]
set riscv_dir  [file normalize "$script_dir/../../riscv"]
set platform_dir [file normalize "$script_dir/../../platform/Xilinx"]

puts "INFO: RTL dir     = $rtl_dir"
puts "INFO: RISCV dir   = $riscv_dir"
puts "INFO: Platform dir= $platform_dir"

#==============================================================================
# 1. Create project
#==============================================================================
create_project ztachip_zc702 . -part xc7z020clg484-1 -force

# Use board part if ZC702 board files are installed (recommended).
# Remove this line if board files are not installed.
catch {set_property board_part xilinx.com:zc702:part0:1.4 [current_project]}

set_property target_language Verilog [current_project]

#==============================================================================
# 2. Add ztachip RTL sources
#    Order matters: package and config files must come first.
#==============================================================================

# --- VHDL Package & Config (must be first) ---
read_vhdl "$rtl_dir/config.vhd"
read_vhdl "$rtl_dir/ztachip_pkg.vhd"

# --- ALU ---
read_vhdl "$rtl_dir/alu/alu.vhd"

# --- Dataplane ---
read_vhdl "$rtl_dir/dp/dp.vhd"
read_vhdl "$rtl_dir/dp/dp_core.vhd"
read_vhdl "$rtl_dir/dp/dp_fetch.vhd"
read_vhdl "$rtl_dir/dp/dp_fifo.vhd"
read_vhdl "$rtl_dir/dp/dp_gen.vhd"
read_vhdl "$rtl_dir/dp/dp_gen_core.vhd"
read_vhdl "$rtl_dir/dp/dp_sink.vhd"
read_vhdl "$rtl_dir/dp/dp_source.vhd"

# --- Integer ALU ---
read_vhdl "$rtl_dir/ialu/ialu.vhd"
read_vhdl "$rtl_dir/ialu/iregister_file.vhd"
read_vhdl "$rtl_dir/ialu/iregister_ram.vhd"

# --- PCORE array ---
read_vhdl "$rtl_dir/pcore/core.vhd"
read_vhdl "$rtl_dir/pcore/instr.vhd"
read_vhdl "$rtl_dir/pcore/instr_decoder2.vhd"
read_vhdl "$rtl_dir/pcore/instr_dispatch2.vhd"
read_vhdl "$rtl_dir/pcore/instr_fetch.vhd"
read_vhdl "$rtl_dir/pcore/pcore.vhd"
read_vhdl "$rtl_dir/pcore/register_bank.vhd"
read_vhdl "$rtl_dir/pcore/register_file.vhd"
read_vhdl "$rtl_dir/pcore/rom.vhd"
read_vhdl "$rtl_dir/pcore/stream.vhd"
read_vhdl "$rtl_dir/pcore/xregister_file.vhd"

# --- FPU ---
read_vhdl "$rtl_dir/fpu/falu_core.vhd"
read_vhdl "$rtl_dir/fpu/falu_vector.vhd"
read_vhdl "$rtl_dir/fpu/falu2.vhd"
read_vhdl "$rtl_dir/fpu/falu.vhd"
read_vhdl "$rtl_dir/fpu/fp12.vhd"
read_vhdl "$rtl_dir/fpu/fp2int.vhd"
read_vhdl "$rtl_dir/fpu/fp_floor.vhd"
read_vhdl "$rtl_dir/fpu/fpmax.vhd"
read_vhdl "$rtl_dir/fpu/fpu.vhd"

# --- SOC AXI infrastructure ---
read_vhdl "$rtl_dir/soc/axi/axi_apb_bridge.vhd"
read_vhdl "$rtl_dir/soc/axi/axi_merge.vhd"
read_vhdl "$rtl_dir/soc/axi/axi_merge_read.vhd"
read_vhdl "$rtl_dir/soc/axi/axi_merge_write.vhd"
read_vhdl "$rtl_dir/soc/axi/axi_read.vhd"
read_vhdl "$rtl_dir/soc/axi/axi_split.vhd"
read_vhdl "$rtl_dir/soc/axi/axi_split_read.vhd"
read_vhdl "$rtl_dir/soc/axi/axi_split_write.vhd"
read_vhdl "$rtl_dir/soc/axi/axi_stream_read.vhd"
read_vhdl "$rtl_dir/soc/axi/axi_stream_write.vhd"
read_vhdl "$rtl_dir/soc/axi/axi_write.vhd"
read_vhdl "$rtl_dir/soc/axi/axi_ram_read.vhd"
read_vhdl "$rtl_dir/soc/axi/axi_ram_write.vhd"
read_vhdl "$rtl_dir/soc/axi/axi_resize_read.vhd"
read_vhdl "$rtl_dir/soc/axi/axi_resize_write.vhd"

# --- SOC peripherals ---
read_vhdl "$rtl_dir/soc/peripherals/camera.vhd"
read_vhdl "$rtl_dir/soc/peripherals/gpio.vhd"
read_vhdl "$rtl_dir/soc/peripherals/vga.vhd"
read_vhdl "$rtl_dir/soc/peripherals/time.vhd"
read_vhdl "$rtl_dir/soc/peripherals/pmu.vhd"
read_vhdl "$rtl_dir/soc/peripherals/uart.vhd"
read_vhdl "$rtl_dir/soc/peripherals/ethlite.vhd"

# --- SOC base ---
read_vhdl "$rtl_dir/soc/soc_base.vhd"
read_vhdl "$rtl_dir/soc/tcm.vhd"

# --- Top-level ztachip blocks ---
read_vhdl "$rtl_dir/top/axilite.vhd"
read_vhdl "$rtl_dir/top/cell.vhd"
read_vhdl "$rtl_dir/top/ddr_rx.vhd"
read_vhdl "$rtl_dir/top/ddr_tx.vhd"
read_vhdl "$rtl_dir/top/sram.vhd"
read_vhdl "$rtl_dir/top/sram_core.vhd"
read_vhdl "$rtl_dir/top/ztachip.vhd"

# --- Utility modules ---
read_vhdl "$rtl_dir/util/shifter_l.vhd"
read_vhdl "$rtl_dir/util/shifter.vhd"
read_vhdl "$rtl_dir/util/ramw2.vhd"
read_vhdl "$rtl_dir/util/ramw.vhd"
read_vhdl "$rtl_dir/util/ram2r1w.vhd"
read_vhdl "$rtl_dir/util/multiplier.vhd"
read_vhdl "$rtl_dir/util/fifow.vhd"
read_vhdl "$rtl_dir/util/fifo.vhd"
read_vhdl "$rtl_dir/util/delayv.vhd"
read_vhdl "$rtl_dir/util/delayi.vhd"
read_vhdl "$rtl_dir/util/delay.vhd"
read_vhdl "$rtl_dir/util/arbiter.vhd"
read_vhdl "$rtl_dir/util/afifo.vhd"
read_vhdl "$rtl_dir/util/afifo2.vhd"
read_vhdl "$rtl_dir/util/adder.vhd"

# --- Xilinx platform primitives (BRAM, DPRAM, FP32, shift) ---
read_verilog "$platform_dir/CCD_SYNC.v"
read_verilog "$platform_dir/SYNC_LATCH.v"
read_verilog "$platform_dir/SHIFT.v"
read_verilog "$platform_dir/DPRAM_BE.v"
read_verilog "$platform_dir/DPRAM_DUAL_CLOCK.v"
read_verilog "$platform_dir/DPRAM.v"
read_verilog "$platform_dir/SPRAM_BE.v"
read_verilog "$platform_dir/SPRAM.v"
read_verilog "$platform_dir/FP32_MUL.v"
read_verilog "$platform_dir/FP32_ADDSUB.v"

# --- VexRiscv RISC-V (uses Xilinx BSCANE2 JTAG tap - works in Zynq PL) ---
read_verilog "$riscv_dir/xilinx_jtag/riscv.v"

# --- ZC702 top-level ---
read_verilog "$script_dir/main_zc702.v"

# --- XDC constraints ---
read_xdc "$script_dir/main_zc702.xdc"

update_compile_order -fileset sources_1

#==============================================================================
# 3. Floating-point IP instances (required by FPU in ztachip)
#    These are the same IPs used in the Arty A7 design.
#==============================================================================

# FP32 Add/Subtract (4-cycle latency, non-blocking)
create_ip -name floating_point \
          -vendor xilinx.com -library ip -version 7.1 \
          -module_name float_addsub
set_property -dict [list \
    CONFIG.Operation_Type  {Add_Subtract} \
    CONFIG.Maximum_Latency {false} \
    CONFIG.C_Latency       {4} \
    CONFIG.Flow_Control    {NonBlocking} \
] [get_ips float_addsub]
generate_target all [get_files float_addsub.xci]

# FP32 Multiply (4-cycle latency, non-blocking)
create_ip -name floating_point \
          -vendor xilinx.com -library ip -version 7.1 \
          -module_name float_mul
set_property -dict [list \
    CONFIG.operation_type  {Multiply} \
    CONFIG.Maximum_Latency {false} \
    CONFIG.C_Latency       {4} \
    CONFIG.Flow_Control    {NonBlocking} \
] [get_ips float_mul]
generate_target all [get_files float_mul.xci]

#==============================================================================
# 4. Create Zynq PS Block Design
#    Sources zynq_ps_bd.tcl which defines and validates the block design.
#==============================================================================
puts "INFO: Creating Zynq PS block design..."
source "$script_dir/zynq_ps_bd.tcl" -notrace

# Generate the BD wrapper (produces zynq_system_wrapper.v)
make_wrapper -files [get_files zynq_system.bd] -top
add_files -norecurse \
    [glob [get_property directory [current_project]]/ztachip_zc702.gen/sources_1/bd/zynq_system/hdl/zynq_system_wrapper.v]
set_property synth_checkpoint_mode None [get_files zynq_system.bd]
generate_target all [get_files zynq_system.bd]

#==============================================================================
# 5. Set top module and compile order
#==============================================================================
set_property top main_zc702 [current_fileset]
update_compile_order -fileset sources_1

puts "INFO: ============================================================"
puts "INFO: Project created successfully!"
puts "INFO:"
puts "INFO: NEXT STEPS:"
puts "INFO:   1. Review synthesis settings (Tools > Settings > Synthesis)"
puts "INFO:      - Strategy: Vivado Synthesis Defaults"
puts "INFO:   2. Run synthesis:     launch_runs synth_1 -jobs 4"
puts "INFO:   3. Check utilization: open_run synth_1; report_utilization"
puts "INFO:   4. Run implementation: launch_runs impl_1 -to_step write_bitstream -jobs 4"
puts "INFO:   5. Program board:     Hardware Manager > Program Device"
puts "INFO: ============================================================"
