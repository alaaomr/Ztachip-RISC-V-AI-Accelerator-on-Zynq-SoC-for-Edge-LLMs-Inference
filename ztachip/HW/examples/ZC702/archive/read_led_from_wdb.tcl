# read_led_from_wdb.tcl — check what signals have real data in wdb

# Jump to near end of sim
catch { goto -time 14600000000 -unit ps }

# Check clk - sanity check to see if wdb has actual data
set clk_val [get_value /tb_main/clk]
puts "CLK at t~14.6ms: $clk_val"

set led_val [get_value /tb_main/led_out]
puts "led_out at t~14.6ms: $led_val"

# Try progressively deeper paths
puts ""
puts "=== Trying deeper paths ==="
set objs [get_objects /tb_main/dut]
puts "dut: $objs"

quit
