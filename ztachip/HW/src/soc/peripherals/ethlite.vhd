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
----------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity ethlite is
   PORT (
      signal clock_in              : IN STD_LOGIC;
      signal reset_in              : IN STD_LOGIC;

      signal apb_paddr             : IN STD_LOGIC_VECTOR(19 downto 0);
      signal apb_penable           : IN STD_LOGIC;
      signal apb_pready            : OUT STD_LOGIC;
      signal apb_pwrite            : IN STD_LOGIC;
      signal apb_pwdata            : IN STD_LOGIC_VECTOR(31 downto 0);
      signal apb_prdata            : OUT STD_LOGIC_VECTOR(31 downto 0);
      signal apb_pslverror         : OUT STD_LOGIC;

      signal phy_tx_clk            : IN STD_LOGIC;
      signal phy_rx_clk            : IN STD_LOGIC;
      signal phy_crs               : IN STD_LOGIC;
      signal phy_dv                : IN STD_LOGIC;
      signal phy_rx_data           : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
      signal phy_col               : IN STD_LOGIC;
      signal phy_rx_er             : IN STD_LOGIC;
      signal phy_rst_n             : OUT STD_LOGIC;
      signal phy_tx_en             : OUT STD_LOGIC;
      signal phy_tx_data           : OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
      signal phy_mdio_i            : IN STD_LOGIC;
      signal phy_mdio_o            : OUT STD_LOGIC;
      signal phy_mdio_t            : OUT STD_LOGIC;
      signal phy_mdc               : OUT STD_LOGIC
    );
end ethlite;
  
architecture Behavioral of ethlite is  

COMPONENT axi_ethernetlite_0 IS
   PORT (
      s_axi_aclk : IN STD_LOGIC;
      s_axi_aresetn : IN STD_LOGIC;
      ip2intc_irpt : OUT STD_LOGIC;
      s_axi_awaddr : IN STD_LOGIC_VECTOR(12 DOWNTO 0);
      s_axi_awvalid : IN STD_LOGIC;
      s_axi_awready : OUT STD_LOGIC;
      s_axi_wdata : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
      s_axi_wstrb : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
      s_axi_wvalid : IN STD_LOGIC;
      s_axi_wready : OUT STD_LOGIC;
      s_axi_bresp : OUT STD_LOGIC_VECTOR(1 DOWNTO 0);
      s_axi_bvalid : OUT STD_LOGIC;
      s_axi_bready : IN STD_LOGIC;
      s_axi_araddr : IN STD_LOGIC_VECTOR(12 DOWNTO 0);
      s_axi_arvalid : IN STD_LOGIC;
      s_axi_arready : OUT STD_LOGIC;
      s_axi_rdata : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
      s_axi_rresp : OUT STD_LOGIC_VECTOR(1 DOWNTO 0);
      s_axi_rvalid : OUT STD_LOGIC;
      s_axi_rready : IN STD_LOGIC;
      phy_tx_clk : IN STD_LOGIC;
      phy_rx_clk : IN STD_LOGIC;
      phy_crs : IN STD_LOGIC;
      phy_dv : IN STD_LOGIC;
      phy_rx_data : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
      phy_col : IN STD_LOGIC;
      phy_rx_er : IN STD_LOGIC;
      phy_rst_n : OUT STD_LOGIC;
      phy_tx_en : OUT STD_LOGIC;
      phy_tx_data : OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
      phy_mdio_i : IN STD_LOGIC;
      phy_mdio_o : OUT STD_LOGIC;
      phy_mdio_t : OUT STD_LOGIC;
      phy_mdc : OUT STD_LOGIC
   );
END COMPONENT;

SIGNAL s_axi_awaddr:STD_LOGIC_VECTOR(12 DOWNTO 0);
SIGNAL s_axi_awvalid:STD_LOGIC;
SIGNAL s_axi_awready:STD_LOGIC;
SIGNAL s_axi_wdata:STD_LOGIC_VECTOR(31 DOWNTO 0);
SIGNAL s_axi_wstrb:STD_LOGIC_VECTOR(3 DOWNTO 0);
SIGNAL s_axi_wvalid:STD_LOGIC;
SIGNAL s_axi_wready:STD_LOGIC;
SIGNAL s_axi_bresp:STD_LOGIC_VECTOR(1 DOWNTO 0);
SIGNAL s_axi_bvalid:STD_LOGIC;
SIGNAL s_axi_bready:STD_LOGIC;
SIGNAL s_axi_araddr:STD_LOGIC_VECTOR(12 DOWNTO 0);
SIGNAL s_axi_arvalid:STD_LOGIC;
SIGNAL s_axi_arready:STD_LOGIC;
SIGNAL s_axi_rdata:STD_LOGIC_VECTOR(31 DOWNTO 0);
SIGNAL s_axi_rresp:STD_LOGIC_VECTOR(1 DOWNTO 0);
SIGNAL s_axi_rvalid:STD_LOGIC;
SIGNAL s_axi_rready:STD_LOGIC;
SIGNAL match:STD_LOGIC;
SIGNAL read:STD_LOGIC;
SIGNAL write:STD_LOGIC;
SIGNAL pready:STD_LOGIC;
SIGNAL prdata:STD_LOGIC_VECTOR(31 downto 0);
SIGNAL pslverror:STD_LOGIC;
SIGNAL awready:STD_LOGIC;
SIGNAL arready:STD_LOGIC;
SIGNAL wready:STD_LOGIC;
SIGNAL awvalid_sent_r:STD_LOGIC;
SIGNAL arvalid_sent_r:STD_LOGIC;
SIGNAL wvalid_sent_r:STD_LOGIC;

-- signal declarations here
begin

ethlite_i:axi_ethernetlite_0
   PORT MAP(
      s_axi_aclk => clock_in,
      s_axi_aresetn => reset_in,
      ip2intc_irpt => open,
      s_axi_awaddr => s_axi_awaddr,
      s_axi_awvalid => s_axi_awvalid,
      s_axi_awready => s_axi_awready,
      s_axi_wdata => s_axi_wdata,
      s_axi_wstrb => s_axi_wstrb,
      s_axi_wvalid => s_axi_wvalid,
      s_axi_wready => s_axi_wready,
      s_axi_bresp => s_axi_bresp,
      s_axi_bvalid => s_axi_bvalid,
      s_axi_bready => s_axi_bready,
      s_axi_araddr => s_axi_araddr,
      s_axi_arvalid => s_axi_arvalid,
      s_axi_arready => s_axi_arready,
      s_axi_rdata => s_axi_rdata,
      s_axi_rresp => s_axi_rresp,
      s_axi_rvalid => s_axi_rvalid,
      s_axi_rready => s_axi_rready,
      phy_tx_clk => phy_tx_clk,
      phy_rx_clk => phy_rx_clk,
      phy_crs => phy_crs,
      phy_dv => phy_dv,
      phy_rx_data => phy_rx_data,
      phy_col => phy_col,
      phy_rx_er => phy_rx_er,
      phy_rst_n => phy_rst_n,
      phy_tx_en => phy_tx_en,
      phy_tx_data => phy_tx_data,
      phy_mdio_i => phy_mdio_i,
      phy_mdio_o => phy_mdio_o,
      phy_mdio_t => phy_mdio_t,
      phy_mdc => phy_mdc
  );

awready <= s_axi_awready;

arready <= s_axi_arready;

wready <= s_axi_wready;

apb_pready <=  pready when (match='1') else '0';

apb_prdata <= prdata  when (match='1') else (others=>'Z');

apb_pslverror <= pslverror when (match='1') else 'Z';

match <= apb_penable;

read <= match and (not apb_pwrite);

s_axi_araddr <= apb_paddr(s_axi_araddr'length-1 downto 0);

s_axi_arvalid <= read and (not arvalid_sent_r);

s_axi_rready <= '1';

write <= match and (apb_pwrite);

s_axi_awaddr <= apb_paddr(s_axi_awaddr'length-1 downto 0);

s_axi_awvalid <= write and (not awvalid_sent_r);

s_axi_bready <= '1';

s_axi_wdata <= apb_pwdata;

s_axi_wstrb <= (others=>'1');

s_axi_wvalid <= write and (not wvalid_sent_r);

prdata <= s_axi_rdata;

pready <= (s_axi_rvalid or s_axi_bvalid);

pslverror <= '0';

process(clock_in)
begin
   if reset_in = '0' then
      awvalid_sent_r <= '0';
      arvalid_sent_r <= '0';
      wvalid_sent_r <= '0';
   else
      if rising_edge(clock_in) then
         if(pready='1') then
            -- Transaction completed
            awvalid_sent_r <= '0';
            wvalid_sent_r <= '0';
            arvalid_sent_r <= '0';
         end if;
         if(read='1' and arready='1') then
            arvalid_sent_r <= '1';
         end if;
         if(write='1' and awready='1') then
            awvalid_sent_r <= '1';
         end if;
         if(write='1' and wready='1') then
            wvalid_sent_r <= '1';
         end if;
      end if;
   end if;  
end process;

end Behavioral;
