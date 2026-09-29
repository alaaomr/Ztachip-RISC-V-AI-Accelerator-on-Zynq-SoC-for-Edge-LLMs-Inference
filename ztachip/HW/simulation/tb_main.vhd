---------------------------------------------------------------------------
-- tb_main.vhd — Clock wrapper for ztachip simulation
--
-- The "main" testbench needs an external clock on its "clk" port.
-- This wrapper generates the clock and connects it.
--
-- Clock: 250 MHz (4 ns period)
--   → clk_x2_main = 250 MHz (inside main.vhd)
--   → clk_main    = 125 MHz (divided by 2 inside main.vhd)
--
-- This file has NO ports — it is the true simulation top.
-- Set top = tb_main in Vivado simulation settings.
---------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_main is
   -- No ports: this is the top of the simulation
end tb_main;

architecture tb of tb_main is

   -- Clock period: 4 ns = 250 MHz
   -- (main.vhd divides by 2 internally, so clk_main = 125 MHz)
   constant CLK_PERIOD : time := 4 ns;

   signal clk     : std_logic := '0';
   signal led_out : std_logic_vector(3 downto 0);

begin

   -- Clock generator: toggles every half period
   clk <= not clk after CLK_PERIOD / 2;

   -- Instantiate the ztachip testbench
   dut : entity work.main
      port map (
         clk     => clk,
         led_out => led_out
      );

   -- Monitor: print led_out to the log whenever it changes.
   -- This lets us track test progress in simulate.log without needing waveforms.
   led_monitor : process(led_out)
      variable dec : integer;
   begin
      if led_out /= "UUUU" and led_out /= "XXXX" then
         dec := to_integer(unsigned(led_out));
         report "LED_OUT_CHANGE: led_out = " & integer'image(dec) &
                " at sim_time=" & time'image(now)
         severity note;
      end if;
   end process;

end tb;
