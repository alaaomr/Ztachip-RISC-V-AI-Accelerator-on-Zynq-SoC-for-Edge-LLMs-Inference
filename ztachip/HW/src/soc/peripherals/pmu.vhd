---------------------------------------------------------------------------
-- pmu.vhd  -  Performance Monitoring Unit (APB peripheral, device id 7)
--
-- Phase-2 on-silicon profiling for ztachip on the ZC702.
--
-- MINIMAL version: only the 4 core memory-bound counters, to keep the clk_main
-- flip-flop load tiny (the base design closes at ~zero timing margin, and the
-- worst path is the TCM dual-pump clk_x2->clk_main crossing, which is sensitive
-- to clk_main load/placement). Coherent reads via a 1-bit FREEZE.
--
--   CYCLES    : free-running cycle counter (fixes the dead APB timer)
--   RD_BEATS  : DDR read data beats (rvalid & rready)  -> read bandwidth
--   RD_STALL  : read starvation cycles (rready & !rvalid) -> memory-bound proof
--   RD_ACTIVE : DDR read busy cycles (arvalid | rvalid)  -> read duty cycle
--
-- Entity ports are unchanged from the full version (so soc_base / ztachip_pkg
-- need no edits); the unused tap inputs simply drive nothing. The dropped
-- registers' read addresses return 0.
--
-- CTRL (write): bit0=clear (one-shot), bit1=freeze (1=stop counting, 0=run).
-- Dedicated prdata/pready (explicit mux in soc_base); no ztachip-core edits.
---------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.config.all;
use work.ztachip_pkg.all;

entity PMU is
   PORT (
      signal clock_in        : IN  STD_LOGIC;
      signal reset_in        : IN  STD_LOGIC;

      signal apb_paddr       : IN  STD_LOGIC_VECTOR(19 downto 0);
      signal apb_penable     : IN  STD_LOGIC;
      signal apb_pready      : OUT STD_LOGIC;
      signal apb_pwrite      : IN  STD_LOGIC;
      signal apb_pwdata      : IN  STD_LOGIC_VECTOR(31 downto 0);
      signal apb_prdata      : OUT STD_LOGIC_VECTOR(31 downto 0);
      signal apb_pslverror   : OUT STD_LOGIC;

      signal ddr_arvalid     : IN  STD_LOGIC;
      signal ddr_arready     : IN  STD_LOGIC;
      signal ddr_rvalid      : IN  STD_LOGIC;
      signal ddr_rready      : IN  STD_LOGIC;
      signal ddr_awvalid     : IN  STD_LOGIC;
      signal ddr_awready     : IN  STD_LOGIC;
      signal ddr_wvalid      : IN  STD_LOGIC;
      signal ddr_wready      : IN  STD_LOGIC;

      signal ctrl_awvalid    : IN  STD_LOGIC;
      signal ctrl_awready    : IN  STD_LOGIC
   );
end PMU;

architecture Behavioral of PMU is
   signal cyc_r      : unsigned(31 downto 0) := (others=>'0');
   signal rdbeat_r   : unsigned(31 downto 0) := (others=>'0');
   signal rdstall_r  : unsigned(31 downto 0) := (others=>'0');
   signal rdact_r    : unsigned(31 downto 0) := (others=>'0');
   signal frozen_r   : std_logic := '0';

   signal sel        : std_logic;
   signal addr       : std_logic_vector(apb_addr_len_c-1 downto 0);
   signal write_ctrl : std_logic;
   signal do_clear   : std_logic;
begin

   addr <= apb_paddr(apb_addr_len_c-1 downto 0);

   sel <= '1' when (apb_penable='1' and
                    apb_paddr(19 downto 16)=std_logic_vector(to_unsigned(apb_pmu_id_c,4)))
              else '0';
   apb_pready    <= sel;
   apb_pslverror <= '0';

   write_ctrl <= '1' when (sel='1' and apb_pwrite='1' and
                           addr=std_logic_vector(to_unsigned(apb_pmu_ctrl_c,apb_addr_len_c)))
                     else '0';
   do_clear <= '1' when (write_ctrl='1' and apb_pwdata(0)='1') else '0';

   -- read mux (combinational, dedicated prdata; live counters)
   apb_prdata <=
      std_logic_vector(cyc_r)     when addr=std_logic_vector(to_unsigned(apb_pmu_cycles_c,apb_addr_len_c))   else
      std_logic_vector(rdbeat_r)  when addr=std_logic_vector(to_unsigned(apb_pmu_rdbeat_c,apb_addr_len_c))   else
      std_logic_vector(rdstall_r) when addr=std_logic_vector(to_unsigned(apb_pmu_rdstall_c,apb_addr_len_c))  else
      std_logic_vector(rdact_r)   when addr=std_logic_vector(to_unsigned(apb_pmu_rdactive_c,apb_addr_len_c)) else
      (others=>'0');

   process(clock_in)
   begin
      if reset_in='0' then
         cyc_r<=(others=>'0'); rdbeat_r<=(others=>'0');
         rdstall_r<=(others=>'0'); rdact_r<=(others=>'0'); frozen_r<='0';
      elsif rising_edge(clock_in) then
         if write_ctrl='1' then frozen_r <= apb_pwdata(1); end if;  -- bit1 = freeze
         if do_clear='1' then
            cyc_r<=(others=>'0'); rdbeat_r<=(others=>'0');
            rdstall_r<=(others=>'0'); rdact_r<=(others=>'0');
         elsif frozen_r='0' then
            cyc_r <= cyc_r + 1;
            if (ddr_rvalid='1'  and ddr_rready='1') then rdbeat_r  <= rdbeat_r  + 1; end if;
            if (ddr_rready='1'  and ddr_rvalid='0') then rdstall_r <= rdstall_r + 1; end if;
            if (ddr_arvalid='1' or  ddr_rvalid='1') then rdact_r   <= rdact_r   + 1; end if;
         end if;
      end if;
   end process;

end Behavioral;
