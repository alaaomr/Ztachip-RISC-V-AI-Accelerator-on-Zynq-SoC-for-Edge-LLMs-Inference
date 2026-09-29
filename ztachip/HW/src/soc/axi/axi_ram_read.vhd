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
-- Convert from AXI to RAM read with constant latency
----------------------------------------------------------------------------

library std;
use std.standard.all;
LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE std.textio.all;
USE ieee.std_logic_textio.all;
use IEEE.numeric_std.all;
use work.ztachip_pkg.all;

entity axi_ram_read is
   generic(
      RAM_DEPTH:integer;
      RAM_LATENCY:integer
   );
   port(   
      axislave_clock_in    :IN STD_LOGIC;
      axislave_reset_in    :IN STD_LOGIC;
      axislave_araddr_in   :IN STD_LOGIC_VECTOR(31 downto 0);
      axislave_arburst_in  :IN STD_LOGIC_VECTOR(1 downto 0);
      axislave_arlen_in    :IN STD_LOGIC_VECTOR(7 downto 0);
      axislave_arready_out :OUT STD_LOGIC;
      axislave_arsize_in   :IN STD_LOGIC_VECTOR(2 downto 0);
      axislave_arvalid_in  :IN STD_LOGIC;
      axislave_rdata_out   :OUT STD_LOGIC_VECTOR(31 downto 0);
      axislave_rlast_out   :OUT STD_LOGIC;
      axislave_rready_in   :IN STD_LOGIC;
      axislave_rresp_out   :OUT STD_LOGIC_VECTOR(1 downto 0);
      axislave_rvalid_out  :OUT STD_LOGIC;

      ram_q_in             :IN std_logic_vector(31 downto 0);
      ram_raddr_out        :OUT std_logic_vector(RAM_DEPTH-1 downto 0);
      ram_read_out         :OUT std_logic
   );
end axi_ram_read;

---
-- This top level component for simulatio
---

architecture rtl of axi_ram_read is

constant FIFO_DEPTH:integer:=4;

constant MAX_LATENCY:integer:=RAM_LATENCY+4;

signal read_addr_r:unsigned(31 downto 0);
signal read_len_r:unsigned(7 downto 0);
signal read_size_r:std_logic_vector(2 downto 0);
signal rvalid_r:std_logic;
signal rlast_r:std_logic;
signal rvalid_delay:std_logic;
signal rlast_delay:std_logic;
signal stall:std_logic;

signal fifo_write_data:std_logic_vector(32 downto 0);
signal fifo_write:std_logic;
signal fifo_read:std_logic;
signal fifo_read_data:std_logic_vector(32 downto 0);
signal fifo_empty:std_logic;
signal fifo_full:std_logic;
SIGNAL fifo_wused:std_logic_vector(FIFO_DEPTH-1 DOWNTO 0);

begin

stall <= '1' when (unsigned(not fifo_wused) < to_unsigned(MAX_LATENCY,FIFO_DEPTH)) else '0';

fifo_write_data <= rlast_delay & ram_q_in;

fifo_write <= rvalid_delay;

fifo_read <= axislave_rready_in and (not fifo_empty);

axislave_rdata_out <= fifo_read_data(31 downto 0);

axislave_rlast_out <= fifo_read_data(32);

axislave_rvalid_out <= (not fifo_empty);

axislave_rresp_out <= (others=>'0');

axislave_arready_out <= '1' when (stall='0' and read_len_r=to_unsigned(0,read_len_r'length))
               else '0';

ram_raddr_out <= std_logic_vector(read_addr_r(ram_raddr_out'length-1 downto 0));

ram_read_out <= rvalid_r;

resp_fifo:scfifo
   generic map
   (
      DATA_WIDTH=>33,
      FIFO_DEPTH=>FIFO_DEPTH,
      LOOKAHEAD=>TRUE,
      ALMOST_FULL=>(2**FIFO_DEPTH)-MAX_LATENCY
   )
   port map 
   (
      clock_in=>axislave_clock_in,
      reset_in=>axislave_reset_in,
      data_in=>fifo_write_data,
      write_in=>fifo_write,
      read_in=>fifo_read,
      q_out=>fifo_read_data,
      empty_out=>fifo_empty,
      full_out=>fifo_full,
      ravail_out=>open,
      wused_out=>fifo_wused,
      almost_full_out=>open
   );

delay_i1: delay generic map(DEPTH => RAM_LATENCY) 
            port map(clock_in => axislave_clock_in,
                     reset_in => axislave_reset_in,
                     in_in=>rvalid_r,
                     out_out=>rvalid_delay,
                     enable_in=>'1');

delay_i2: delay generic map(DEPTH => RAM_LATENCY) 
            port map(clock_in => axislave_clock_in,
                     reset_in => axislave_reset_in,
                     in_in=>rlast_r,
                     out_out=>rlast_delay,
                     enable_in=>'1');

process(axislave_clock_in,axislave_reset_in)
begin
if axislave_reset_in = '0' then
   read_addr_r <= (others=>'0');
   read_len_r <= (others=>'0');
   read_size_r <= (others=>'0');
   rvalid_r <= '0';
   rlast_r <= '0';
else
   if axislave_clock_in'event and axislave_clock_in='1' then
      if(stall='0') then
         if(read_len_r=to_unsigned(0,read_len_r'length)) then
            -- Fetch new request
            if(axislave_arvalid_in='1') then
               if(unsigned(axislave_arlen_in)=0) then
                  rlast_r <= '1';
               else
                  rlast_r <= '0';
               end if;
               read_addr_r <= unsigned(axislave_araddr_in);
               read_len_r <= unsigned(axislave_arlen_in);
               read_size_r <= axislave_arsize_in;
               rvalid_r <= '1';
            else
               rlast_r <= '0';
               read_addr_r <= (others=>'0');
               read_len_r <= (others=>'0');
               read_size_r <= (others=>'0');
               rvalid_r <= '0';
            end if;
         else
            -- Fetch next word
            if(unsigned(read_len_r)=1) then
               rlast_r <= '1';
            else
               rlast_r <= '0';
            end if;
            read_addr_r <= read_addr_r+to_unsigned(4,read_addr_r'length);
            read_len_r <= read_len_r-to_unsigned(1,read_len_r'length);
            rvalid_r <= '1';
         end if;
      else
         rvalid_r <= '0';
      end if;
   end if;
end if;

end process;

end rtl;
