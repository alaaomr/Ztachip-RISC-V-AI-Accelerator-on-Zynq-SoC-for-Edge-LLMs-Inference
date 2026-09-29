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

entity TCM is
   generic(
      RAM_DEPTH:integer
   );
   port(   
      TCM_clk       :IN STD_LOGIC;
      TCM_clk_x2    :IN STD_LOGIC;
      TCM_reset     :IN STD_LOGIC;

      TCM_araddr1   :IN STD_LOGIC_VECTOR(31 downto 0);
      TCM_arburst1  :IN STD_LOGIC_VECTOR(1 downto 0);
      TCM_arlen1    :IN STD_LOGIC_VECTOR(7 downto 0);
      TCM_arready1  :OUT STD_LOGIC;
      TCM_arsize1   :IN STD_LOGIC_VECTOR(2 downto 0);
      TCM_arvalid1  :IN STD_LOGIC;
      TCM_rdata1    :OUT STD_LOGIC_VECTOR(31 downto 0);
      TCM_rlast1    :OUT STD_LOGIC;
      TCM_rready1   :IN STD_LOGIC;
      TCM_rresp1    :OUT STD_LOGIC_VECTOR(1 downto 0);
      TCM_rvalid1   :OUT STD_LOGIC;

      TCM_araddr2   :IN STD_LOGIC_VECTOR(31 downto 0);
      TCM_arburst2  :IN STD_LOGIC_VECTOR(1 downto 0);
      TCM_arlen2    :IN STD_LOGIC_VECTOR(7 downto 0);
      TCM_arready2  :OUT STD_LOGIC;
      TCM_arsize2   :IN STD_LOGIC_VECTOR(2 downto 0);
      TCM_arvalid2  :IN STD_LOGIC;
      TCM_rdata2    :OUT STD_LOGIC_VECTOR(31 downto 0);
      TCM_rlast2    :OUT STD_LOGIC;
      TCM_rready2   :IN STD_LOGIC;
      TCM_rresp2    :OUT STD_LOGIC_VECTOR(1 downto 0);
      TCM_rvalid2   :OUT STD_LOGIC;

      TCM_awaddr    :IN STD_LOGIC_VECTOR(31 downto 0);
      TCM_awburst   :IN STD_LOGIC_VECTOR(1 downto 0);
      TCM_awlen     :IN STD_LOGIC_VECTOR(7 downto 0);
      TCM_awready   :OUT STD_LOGIC;
      TCM_awsize    :IN STD_LOGIC_VECTOR(2 downto 0);
      TCM_awvalid   :IN STD_LOGIC;
      TCM_bready    :IN STD_LOGIC;
      TCM_bresp     :OUT STD_LOGIC_VECTOR(1 downto 0);
      TCM_bvalid    :OUT STD_LOGIC;
      TCM_wdata     :IN STD_LOGIC_VECTOR(31 downto 0);
      TCM_wlast     :IN STD_LOGIC;
      TCM_wready    :OUT STD_LOGIC;
      TCM_wstrb     :IN STD_LOGIC_VECTOR(3 downto 0);
      TCM_wvalid    :IN STD_LOGIC
   );
end TCM;

---
-- This top level component for simulatio
---

architecture rtl of TCM is

signal ram_q1:std_logic_vector(31 downto 0);
signal ram_raddr1:std_logic_vector(RAM_DEPTH-1 downto 0);
signal ram_q2:std_logic_vector(31 downto 0);
signal ram_raddr2:std_logic_vector(RAM_DEPTH-1 downto 0);
signal ram_waddr:std_logic_vector(RAM_DEPTH-3 downto 0);
signal ram_wdata:std_logic_vector(31 downto 0);
signal ram_wren:std_logic;
signal ram_be:std_logic_vector(3 downto 0);

begin


ram_i:ram2r1w
   GENERIC MAP (
        numwords_a=>2**(RAM_DEPTH-2),
        numwords_b=>2**(RAM_DEPTH-2),
        widthad_a=>RAM_DEPTH-2,
        widthad_b=>RAM_DEPTH-2,
        width_a=>32,
        width_b=>32
    )
    PORT MAP (
        clock=>TCM_clk,
        clock_x2=>TCM_clk_x2,
        address_a=>ram_waddr,
        byteena_a=>ram_be,
        data_a=>ram_wdata,
        wren_a=>ram_wren,
        address1_b=>ram_raddr1(ram_raddr1'length-1 downto 2),
        q1_b=>ram_q1,
        address2_b=>ram_raddr2(ram_raddr2'length-1 downto 2),
        q2_b=>ram_q2
    );

TCM_read1_i:axi_ram_read
   generic map(
      RAM_DEPTH=>RAM_DEPTH,
      RAM_LATENCY=>1
   )
   port map(   
      axislave_clock_in=>TCM_clk,
      axislave_reset_in=>TCM_reset,
      axislave_araddr_in=>TCM_araddr1,
      axislave_arburst_in=>TCM_arburst1,
      axislave_arlen_in=>TCM_arlen1,
      axislave_arready_out=>TCM_arready1,
      axislave_arsize_in=>TCM_arsize1,
      axislave_arvalid_in=>TCM_arvalid1,
      axislave_rdata_out=>TCM_rdata1,
      axislave_rlast_out=>TCM_rlast1,
      axislave_rready_in=>TCM_rready1,
      axislave_rresp_out=>TCM_rresp1,
      axislave_rvalid_out=>TCM_rvalid1,
      ram_q_in=>ram_q1,
      ram_raddr_out=>ram_raddr1,
      ram_read_out=>open
   );

TCM_read2_i:axi_ram_read
   generic map(
      RAM_DEPTH=>RAM_DEPTH,
      RAM_LATENCY=>1
   )
   port map(   
      axislave_clock_in=>TCM_clk,
      axislave_reset_in=>TCM_reset,
      axislave_araddr_in=>TCM_araddr2,
      axislave_arburst_in=>TCM_arburst2,
      axislave_arlen_in=>TCM_arlen2,
      axislave_arready_out=>TCM_arready2,
      axislave_arsize_in=>TCM_arsize2,
      axislave_arvalid_in=>TCM_arvalid2,
      axislave_rdata_out=>TCM_rdata2,
      axislave_rlast_out=>TCM_rlast2,
      axislave_rready_in=>TCM_rready2,
      axislave_rresp_out=>TCM_rresp2,
      axislave_rvalid_out=>TCM_rvalid2,
      ram_q_in=>ram_q2,
      ram_raddr_out=>ram_raddr2
   );

TCM_write_i:axi_ram_write
   generic map(
      RAM_DEPTH=>RAM_DEPTH
   )
   port map(   
      axislave_clock_in=>TCM_clk,
      axislave_reset_in=>TCM_reset,

      axislave_awaddr_in=>TCM_awaddr,
      axislave_awburst_in=>TCM_awburst,
      axislave_awlen_in=>TCM_awlen,
      axislave_awready_out=>TCM_awready,
      axislave_awsize_in=>TCM_awsize,
      axislave_awvalid_in=>TCM_awvalid,
      axislave_bready_in=>TCM_bready,
      axislave_bresp_out=>TCM_bresp,
      axislave_bvalid_out=>TCM_bvalid,
      axislave_wdata_in=>TCM_wdata,
      axislave_wlast_in=>TCM_wlast,
      axislave_wready_out=>TCM_wready,
      axislave_wstrb_in=>TCM_wstrb,
      axislave_wvalid_in=>TCM_wvalid,

      ram_waddr_out=>ram_waddr,
      ram_wdata_out=>ram_wdata,
      ram_wren_out=>ram_wren,
      ram_be_out=>ram_be
   );

end rtl;
