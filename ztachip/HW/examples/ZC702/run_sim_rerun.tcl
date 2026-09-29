# =============================================================================
# run_sim_rerun.tcl  — Re-launch LLM kernel simulation (clean restart)
#
# What is different from run_sim_vivado.tcl:
#   1. tb_main.vhd now has a led_monitor process that PRINTS led_out changes
#      to simulate.log — you can track test progress without a waveform viewer.
#   2. This script closes & restarts simulation to pick up the tb_main.vhd edit.
#   3. Runs 20 ms automatically in the Tcl console.
#
# Run from Vivado Tcl console:
#   source ~/Desktop/AIDAChip_Workshop_01/ztachip/HW/examples/ZC702/run_sim_rerun.tcl
#
# When done, open simulate.log and search for "LED_OUT_CHANGE":
#   grep "LED_OUT_CHANGE" ~/Desktop/.../ztachip_zc702.sim/sim_1/behav/xsim/simulate.log
# =============================================================================

set ZTACHIP /home/eslam-elshokafy/Desktop/AIDAChip_Workshop_01/ztachip
set ZC702   $ZTACHIP/HW/examples/ZC702
set SIM_DIR $ZC702/ztachip_zc702.sim/sim_1/behav/xsim

# ---- Open project (safe if already open) -----------------------------------
puts "INFO: Opening project..."
catch {open_project $ZC702/ztachip_zc702.xpr}

puts "INFO: ========================================================="
puts "INFO: LLM Kernel Simulation — Clean Restart with LED Monitoring"
puts "INFO: ========================================================="

# ---- Close any running simulation ------------------------------------------
catch {close_sim -quiet}

# ---- Make sure tb_main.vhd is in the fileset (it was edited) ---------------
set tb_file $ZTACHIP/HW/simulation/tb_main.vhd
add_files -fileset sim_1 -norecurse $tb_file
puts "INFO: tb_main.vhd refreshed (has LED monitor now)."

# ---- Copy the hex firmware -------------------------------------------------
set HEX_SRC $ZTACHIP/SW/build/ztachip_sim.hex
if {![file exists $HEX_SRC]} {
    puts "ERROR: ztachip_sim.hex not found."
    puts "ERROR: Run first:  bash $ZC702/run_sim_build.sh"
    return
}
file mkdir $SIM_DIR
file copy -force $HEX_SRC $SIM_DIR/ztachip_sim.hex
puts "INFO: ztachip_sim.hex copied."

# ---- Set top ---------------------------------------------------------------
set_property top tb_main [get_filesets sim_1]
set_property top_lib xil_defaultlib [get_filesets sim_1]

# ---- Launch simulation -----------------------------------------------------
# Note: metavalue warnings from dp_gen.vhd fill the log. To suppress them,
# after the sim window opens go to:
#   Simulation Settings -> Simulation -> xsim.simulate.xsim.more_options
# or just let the log grow (it won't affect LED_OUT_CHANGE messages).
puts "INFO: Launching simulation..."
launch_simulation

# Suppress the NUMERIC_STD metavalue warning flood (xsim runtime command,
# called after launch so xsim is active):
catch { set_msg_config -severity WARNING -suppress }
puts "INFO: Running 20 ms of simulation time. Please wait (~20 minutes)..."
run 20ms

puts ""
puts "INFO: Simulation finished 20 ms run."
puts "INFO: ========================================================="
puts "INFO: To see test results, run this in a terminal:"
puts "INFO:   grep 'LED_OUT_CHANGE' $SIM_DIR/simulate.log"
puts "INFO: ========================================================="
puts "INFO: Expected LED progression for LLM tests:"
puts "INFO:   led_out=1  : ztaInit done"
puts "INFO:   led_out=2  : residual PASSED"
puts "INFO:   led_out=3  : SwiGLU PASSED"
puts "INFO:   led_out=4  : rms PASSED"
puts "INFO:   led_out=5  : rope PASSED"
puts "INFO:   led_out=6  : softmax PASSED"
puts "INFO:   led_out=7  : k_max PASSED"
puts "INFO:   led_out=8  : cosine PASSED"
puts "INFO:   led_out=9  : sine PASSED  (ALL DONE!)"
puts "INFO: ========================================================="
