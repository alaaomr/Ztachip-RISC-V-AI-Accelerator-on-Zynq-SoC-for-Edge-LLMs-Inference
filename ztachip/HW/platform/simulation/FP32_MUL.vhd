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
-- Float operation in simulation
---

library std;
use std.standard.all;
LIBRARY ieee;
USE ieee.std_logic_1164.all;
use IEEE.numeric_std.all;
use IEEE.MATH_REAL.ALL;
use work.ztachip_pkg.all;

entity FP32_MUL is
   generic
   (
      LATENCY:natural
   );
   port 
   (
      SIGNAL reset_in    : in std_logic;
      SIGNAL clock_in    : in std_logic;
      SIGNAL x1_in       : in fp32_t;
      SIGNAL x2_in       : in fp32_t;
      SIGNAL y_out       : out fp32_t
   );
end FP32_MUL;

architecture rtl of FP32_MUL is
signal y_r:fp32_t;
begin

delay_i:delayv
   generic map(
      SIZE=>fp32_t'length,
      DEPTH=>LATENCY-1
   )
   port map(
      clock_in=>clock_in,
      reset_in=>reset_in,
      in_in=>y_r,
      out_out=>y_out,
      enable_in=>'1'
   );

process(clock_in,reset_in)
variable x1_real:real;
variable x2_real:real;
variable y_real:real;
variable y_fp32:std_logic_vector(31 downto 0);
begin
   if(reset_in='0') then
      y_r <= (others=>'0');
   else
      if(rising_edge(clock_in)) then
         x1_real := float32_to_real(x1_in);
         x2_real := float32_to_real(x2_in);
         y_real := x1_real * x2_real;
         y_fp32 := real_to_float32(y_real);
         y_r <= y_fp32; 
      end if;
   end if;
end process;

end rtl;