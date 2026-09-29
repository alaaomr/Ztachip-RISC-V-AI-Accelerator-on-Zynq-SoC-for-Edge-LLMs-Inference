---------------------------------------------------------------------------
-- Copyright [2014] [Ztachip Technologies Inc]
--
-- Author: Vuong Nguyen
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except IN compliance with the License.
-- You may obtain a copy of the License at
--
-- http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to IN writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
------------------------------------------------------------------------------


----------------------------------------------------------------------------
-- This module implements TCM (Tighly coupling memory)
-- It serves as L2 cache for RISCV
----------------------------------------------------------------------------

library std;
use std.standard.all;
LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE std.textio.all;
USE ieee.std_logic_textio.all;
use IEEE.numeric_std.all;
use work.ztachip_pkg.all;

entity axi_ram_write is
   generic(
      RAM_DEPTH:integer
   );
   port(   
      axislave_clock_in     :IN STD_LOGIC;
      axislave_reset_in     :IN STD_LOGIC;

      axislave_awaddr_in    :IN STD_LOGIC_VECTOR(31 downto 0);
      axislave_awburst_in   :IN STD_LOGIC_VECTOR(1 downto 0);
      axislave_awlen_in     :IN STD_LOGIC_VECTOR(7 downto 0);
      axislave_awready_out  :OUT STD_LOGIC;
      axislave_awsize_in    :IN STD_LOGIC_VECTOR(2 downto 0);
      axislave_awvalid_in   :IN STD_LOGIC;
      axislave_bready_in    :IN STD_LOGIC;
      axislave_bresp_out    :OUT STD_LOGIC_VECTOR(1 downto 0);
      axislave_bvalid_out   :OUT STD_LOGIC;
      axislave_wdata_in     :IN STD_LOGIC_VECTOR(31 downto 0);
      axislave_wlast_in     :IN STD_LOGIC;
      axislave_wready_out   :OUT STD_LOGIC;
      axislave_wstrb_in     :IN STD_LOGIC_VECTOR(3 downto 0);
      axislave_wvalid_in    :IN STD_LOGIC;

      ram_waddr_out         :OUT std_logic_vector(RAM_DEPTH-3 downto 0);
      ram_wdata_out         :OUT std_logic_vector(31 downto 0);
      ram_wren_out          :OUT std_logic;
      ram_be_out            :OUT std_logic_vector(3 downto 0)
   );
end axi_ram_write;

---
-- This top level component for simulatio
---

architecture rtl of axi_ram_write is

signal write_addr_r:unsigned(31 downto 0);
signal write_len_r:unsigned(7 downto 0);
signal write_size_r:std_logic_vector(2 downto 0);
signal write_busy_r:std_logic;
signal wready:std_logic;

begin

wready <= write_busy_r and axislave_bready_in;

axislave_awready_out <= '1' when (write_busy_r='0') or 
                     (write_busy_r='1' and wready='1' and axislave_wvalid_in='1' and 
                     write_len_r=to_unsigned(0,write_len_r'length))
                     else '0';

axislave_wready_out <= wready;

axislave_bvalid_out <= '1' when (wready='1' and axislave_wvalid_in='1' and write_len_r=to_unsigned(0,write_len_r'length)) else '0';

axislave_bresp_out <= (others=>'0');

ram_waddr_out <= std_logic_vector(write_addr_r(ram_waddr_out'length+1 downto 2));

ram_wdata_out <= axislave_wdata_in;

ram_be_out <= axislave_wstrb_in;

ram_wren_out <= write_busy_r and wready and axislave_wvalid_in;

process(axislave_clock_in,axislave_reset_in)
begin
if axislave_reset_in = '0' then
   write_addr_r <= (others=>'0');
   write_len_r <= (others=>'0');
   write_size_r <= (others=>'0');
   write_busy_r <= '0';
else
   if axislave_clock_in'event and axislave_clock_in='1' then
      if(write_busy_r='1') then
         if(wready='1' and axislave_wvalid_in='1') then
            if(write_len_r=to_unsigned(0,write_len_r'length)) then
               write_addr_r <= unsigned(axislave_awaddr_in);
               write_len_r <= unsigned(axislave_awlen_in);
               write_size_r <= axislave_awsize_in;
               write_busy_r <= axislave_awvalid_in;
            else
               write_addr_r <= write_addr_r+to_unsigned(4,write_addr_r'length);
               write_len_r <= write_len_r-to_unsigned(1,write_len_r'length);
            end if;
         end if;
      else
         write_addr_r <= unsigned(axislave_awaddr_in);
         write_len_r <= unsigned(axislave_awlen_in);
         write_size_r <= axislave_awsize_in;
         write_busy_r <= axislave_awvalid_in;
      end if;
   end if;
end if;

end process;

end rtl;
