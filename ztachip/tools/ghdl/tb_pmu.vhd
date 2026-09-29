-- tb_pmu.vhd : self-checking functional testbench for the PMU peripheral.
-- Drives the DDR-AXI tap inputs and reads the PMU registers over APB, asserting
-- the counters increment correctly, clear works, and the latched read path works.
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.config.all;
use work.ztachip_pkg.all;

entity tb_pmu is end tb_pmu;

architecture sim of tb_pmu is
   signal clk        : std_logic := '0';
   signal rstn       : std_logic := '1';
   signal paddr      : std_logic_vector(19 downto 0) := (others=>'0');
   signal penable    : std_logic := '0';
   signal pready     : std_logic;
   signal pwrite     : std_logic := '0';
   signal pwdata     : std_logic_vector(31 downto 0) := (others=>'0');
   signal prdata     : std_logic_vector(31 downto 0);
   signal pslverr    : std_logic;
   signal arvalid,arready,rvalid,rready : std_logic := '0';
   signal awvalid,awready,wvalid,wready : std_logic := '0';
   signal cawvalid,cawready : std_logic := '0';
   signal done : boolean := false;

   function off(c:integer) return std_logic_vector is
   begin return std_logic_vector(to_unsigned(c,20)); end function;
begin
   -- 100 MHz clock
   clk <= not clk after 5 ns when not done else '0';

   dut: PMU port map(
      clock_in=>clk, reset_in=>rstn,
      apb_paddr=>paddr, apb_penable=>penable, apb_pready=>pready,
      apb_pwrite=>pwrite, apb_pwdata=>pwdata, apb_prdata=>prdata, apb_pslverror=>pslverr,
      ddr_arvalid=>arvalid, ddr_arready=>arready, ddr_rvalid=>rvalid, ddr_rready=>rready,
      ddr_awvalid=>awvalid, ddr_awready=>awready, ddr_wvalid=>wvalid, ddr_wready=>wready,
      ctrl_awvalid=>cawvalid, ctrl_awready=>cawready);

   stim: process
      -- read a PMU register (combinational mux) and return its integer value
      procedure rd(constant a:integer; variable v:out integer) is
      begin
         paddr <= off(a); wait for 1 ns; v := to_integer(unsigned(prdata));
      end procedure;
      -- one-cycle APB write
      procedure wr(constant a:integer; constant d:integer) is
      begin
         paddr<=off(a); pwrite<='1'; penable<='1';
         pwdata<=std_logic_vector(to_unsigned(d,32));
         wait until rising_edge(clk);
         penable<='0'; pwrite<='0';
      end procedure;
      variable v : integer;
      variable c1,c2 : integer;
   begin
      rstn <= '1';                       -- '1' = run (active-low reset)
      wait until rising_edge(clk);

      -- 1) CLEAR all counters
      wr(apb_pmu_ctrl_c, 1);

      -- 2) drive exactly 5 DDR read beats (rvalid & rready)
      rvalid<='1'; rready<='1';
      for i in 1 to 5 loop wait until rising_edge(clk); end loop;
      rvalid<='0'; rready<='0';

      -- 3) drive exactly 3 read-starvation cycles (rready & not rvalid)
      rready<='1'; rvalid<='0';
      for i in 1 to 3 loop wait until rising_edge(clk); end loop;
      rready<='0';

      -- 5) FREEZE for a coherent snapshot (bit1=1)
      wr(apb_pmu_ctrl_c, 2);

      -- 6) read back and check the 4 core counters
      rd(apb_pmu_rdbeat_c,  v); report "RDBEAT="  & integer'image(v); assert v=5 report "FAIL rdbeat (exp 5)"  severity failure;
      rd(apb_pmu_rdstall_c, v); report "RDSTALL=" & integer'image(v); assert v=3 report "FAIL rdstall (exp 3)" severity failure;
      rd(apb_pmu_rdactive_c,v); report "RDACTIVE="& integer'image(v); assert v=5 report "FAIL rdactive (exp 5)"severity failure;
      rd(apb_pmu_cycles_c,  v); report "CYCLES="  & integer'image(v); assert v>=8 report "FAIL cycles (exp >=8)" severity failure;

      -- 7) prove the cycle counter is FREE-RUNNING (UNFREEZE first, then it advances)
      wr(apb_pmu_ctrl_c, 0); rd(apb_pmu_cycles_c, c1);
      for i in 1 to 7 loop wait until rising_edge(clk); end loop;
      rd(apb_pmu_cycles_c, c2);
      report "CYC c1=" & integer'image(c1) & " c2=" & integer'image(c2);
      assert c2 > c1 report "FAIL cycle counter not advancing" severity failure;

      report "===== PMU FUNCTIONAL TB PASSED =====" severity note;
      done <= true;
      wait;
   end process;
end sim;
