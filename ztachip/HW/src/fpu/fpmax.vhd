------------------------------------------------------------------------------
-- Copyright [2014] [Ztachip Technologies Inc]
--
-- Author: Vuong Nguyen
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
-- http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
------------------------------------------------------------------------------

---
-- Float to integer conversion
---

library std;
use std.standard.all;
LIBRARY ieee;
USE ieee.std_logic_1164.all;
use IEEE.numeric_std.all;
use work.ztachip_pkg.all;

---
-- This component return the greater value of x1 or x2
---

entity fpmax is
   generic
   (
      LATENCY:natural
   );
   port(
      SIGNAL clock_in : in std_logic;
      SIGNAL reset_in : in std_logic;
      SIGNAL x1_in    : in  fp32_t;
      SIGNAL x2_in    : in  fp32_t;
      SIGNAL y_out    : out fp32_t
   );
end entity;

architecture rtl of fpmax is
signal x1_r,x2_r:fp32_t;
signal y_r:fp32_t;
begin

assert LATENCY >= 2 report "fpmax must have a latency at least 2" severity failure;

GEN1: IF LATENCY > 2 GENERATE
delay_i:delayv
    generic map(
        SIZE=>fp32_t'length,
        DEPTH=>LATENCY-2
    )
    port map(
        clock_in=>clock_in,
        reset_in=>reset_in,
        in_in=>y_r,
        out_out=>y_out,
        enable_in=>'1'
    );
END GENERATE GEN1;

GEN2: IF LATENCY <= 2 GENERATE
y_out <= y_r;
END GENERATE GEN2;



process(clock_in,reset_in)
variable x1_v:unsigned(31 downto 0);
variable x2_v:unsigned(31 downto 0);
begin
   if reset_in = '0' then
      x1_r <= (others=>'0');
      x2_r <= (others=>'0');
      y_r <= (others=>'0');
   else
      if clock_in'event and clock_in='1' then
         x1_r <= x1_in;
         x2_r <= x2_in;
         if x1_r(31) = '1' then
            x1_v := not unsigned(x1_r);
         else
            x1_v := unsigned(x1_r) xor x"80000000";
         end if;

         if x2_r(31) = '1' then
            x2_v := not unsigned(x2_r);
         else
            x2_v := unsigned(x2_r) xor x"80000000";
         end if;

         -- compare
         if x1_v < x2_v then
            y_r <= x2_r;
         else
            y_r <= x1_r;
         end if;
      end if;
   end if;
end process;

end architecture;