# =============================================================================
# Simulation Setup and Launch — ztachip ZC702 Graduation Project
#
# What this script does:
#   1. Opens the existing ZC702 Vivado project
#   2. Adds simulation source files (testbench + platform models + RISC-V model)
#   3. Copies ztachip_sim.hex to the simulation working directory
#   4. Sets simulation top to "main" (the testbench)
#   5. Launches behavioral simulation
#
# What to look for when simulation runs:
#   - "led_out" signal should change (it blinks each time a test passes)
#   - No error messages from the testbench
#   - The RISC-V CPU boots and starts executing the test program
#
# BEFORE running this script, you must have:
#   Run run_sim_build.sh from a terminal to generate ztachip_sim.hex
#
# Run from Vivado Tcl console:
#   source ~/Desktop/AIDAChip_Workshop_01/ztachip/HW/examples/ZC702/run_sim_vivado.tcl
# =============================================================================

puts "INFO: ============================================================"
puts "INFO: Setting up ztachip Simulation"
puts "INFO: ============================================================"

set ZTACHIP /home/eslam-elshokafy/Desktop/AIDAChip_Workshop_01/ztachip
set ZC702   $ZTACHIP/HW/examples/ZC702

# ---- Step 1: Open project ---------------------------------------------------
puts "INFO: Opening project..."
catch {open_project $ZC702/ztachip_zc702.xpr}

# ---- Step 2: Add simulation source files ------------------------------------
# These files only go into sim_1 (simulation fileset), NOT synthesis
puts "INFO: Adding simulation source files to sim_1..."

# The simulation platform replaces Xilinx-specific FPGA primitives with
# generic VHDL models so we can simulate without Xilinx IP.
# Think of it like this: the real FPGA has hardware RAM blocks (BRAM).
# In simulation, we use a software model of those RAM blocks instead.

set sim_files [list]

# Simulation platform (generic BRAM, FP32 models)
foreach f [glob $ZTACHIP/HW/platform/simulation/*.vhd] {
    lappend sim_files $f
}

# Simulation testbench files
lappend sim_files $ZTACHIP/HW/simulation/mem64.vhd
lappend sim_files $ZTACHIP/HW/simulation/axi_protocol_checker.vhd
lappend sim_files $ZTACHIP/HW/simulation/main.vhd
lappend sim_files $ZTACHIP/HW/simulation/tb_main.vhd

# RISC-V (VexRiscv) simulation model
lappend sim_files $ZTACHIP/HW/riscv/sim/riscv.vhd

# Close any existing simulation so file changes (e.g., mem64.vhd RAM_SIZE)
# get picked up on relaunch
catch {close_sim -quiet}

# Add all simulation files to the sim_1 fileset (skip silently if already added)
foreach f $sim_files {
    if {[file exists $f]} {
        if {[catch {add_files -fileset sim_1 -norecurse $f} err]} {
            puts "INFO:   Already in project: [file tail $f]"
        } else {
            puts "INFO:   Added: [file tail $f]"
        }
    } else {
        puts "WARNING: File not found: $f"
    }
}


# ---- Step 3: Copy the hex firmware file ------------------------------------
# The testbench (mem64.vhd) loads ztachip_sim.hex as the "program" in
# simulated memory. This is the RISC-V binary that was compiled by
# run_sim_build.sh. We need to copy it to the simulation working directory.

set HEX_SRC $ZTACHIP/SW/build/ztachip_sim.hex
set SIM_DIR $ZC702/ztachip_zc702.sim/sim_1/behav/xsim

puts "INFO: Checking for ztachip_sim.hex..."
if {![file exists $HEX_SRC]} {
    puts "ERROR: ztachip_sim.hex not found!"
    puts "ERROR: Please run this first from a terminal:"
    puts "ERROR:   bash ~/Desktop/AIDAChip_Workshop_01/ztachip/HW/examples/ZC702/run_sim_build.sh"
    return
}

# Create simulation working directory if it doesn't exist
file mkdir $SIM_DIR

# Copy hex to simulation working directory
file copy -force $HEX_SRC $SIM_DIR/ztachip_sim.hex
puts "INFO: Copied ztachip_sim.hex to simulation directory."

# ---- Step 4: Set simulation top ---------------------------------------------
# tb_main is the true top — it generates the 250MHz clock and connects it
# to "main" (the real testbench in HW/simulation/main.vhd).
# "main" then divides by 2 to get clk_main=125MHz and runs soc_base + mem64.
puts "INFO: Setting simulation top to 'tb_main'..."
set_property top tb_main [get_filesets sim_1]
set_property top_lib xil_defaultlib [get_filesets sim_1]

# ---- Step 5: Launch simulation ---------------------------------------------
puts "INFO: ============================================================"
puts "INFO: Launching behavioral simulation..."
puts "INFO: ============================================================"
puts "INFO: What to look for (LLM kernel tests, light->heavy order):"
puts "INFO:   - led_out = 1 : ztaInit done"
puts "INFO:   - led_out = 2 : test_llm_residual PASSED  (fast)"
puts "INFO:   - led_out = 3 : test_llm_SwiGLU   PASSED  (fast)"
puts "INFO:   - led_out = 4 : test_llm_rms      PASSED  (medium)"
puts "INFO:   - led_out = 5 : test_llm_rope     PASSED  (medium)"
puts "INFO:   - led_out = 6 : test_llm_softmax  PASSED  (medium)"
puts "INFO:   - led_out = 7 : test_llm_k_max    PASSED"
puts "INFO:   - led_out = 8 : test_llm_cosine   PASSED  (slow)"
puts "INFO:   - led_out = 9 : test_llm_sine     PASSED  (slow)"
puts "INFO:   - led_out = A : ALL DONE (looping)"
puts "INFO: ============================================================"
puts "INFO: LLM kernels are bigger workloads than vision kernels."
puts "INFO: Run for at least 20 ms of simulation time:"
puts "INFO:   In the Tcl console type:  run 20ms"
puts "INFO: ============================================================"

# Demote the benign NUMERIC_STD metavalue warning flood (idle datapath lanes
# hold U/X before first use - harmless, but spamming the console slows xsim).
# Keep the first 5 as a record, suppress the rest.
set_msg_config -id "NUMERIC_STD-*" -limit 5

launch_simulation

puts "INFO: Simulation launched! Check the waveform window."
puts "INFO: Add signals to waveform: right-click in Scope panel -> Add to Waveform"
puts "INFO: Key signals to watch: led_out, clk_main, reset"
