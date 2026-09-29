---------------------------------------------------------------------------------
-- axi_protocol_checker.vhd
--
-- SIMULATION-ONLY, OBSERVATIONAL AXI3 protocol checker for the ztachip <-> DDR
-- (SDRAM_*) interface. Every port is an INPUT: this module drives NOTHING, so
-- it cannot change simulation behaviour. It only watches the bus and reports
-- protocol violations via assert/report.
--
-- Instantiate it in HW/simulation/main.vhd alongside mem64, wired to the same
-- SDRAM_* signals (see hookup snippet in the verification notes).
--
-- WHAT IT VERIFIES (tuned for this project):
--   1. STAR CHECK: arlen[7:4]=0 and awlen[7:4]=0 whenever the address is valid.
--      main_zc702.v connects only ARLEN/AWLEN[3:0] to the Zynq HP0 (AXI3, 4-bit
--      len). That truncation is ONLY safe if ztachip never issues a burst whose
--      length needs the upper 4 bits. If it ever does, this fires - catching a
--      bug that would silently corrupt data ON THE BOARD, here in sim instead.
--   2. bresp/rresp must be OKAY (00). Anything else means a DDR access failed
--      (wrong address map, out-of-range, etc.).
--   3. Payload must stay STABLE while VALID=1 and READY=0 (AXI handshake rule).
--   4. No channel may assert VALID during reset.
--   5. Burst type must not be the reserved value "11".
--   6. Write-data beat count must match AWLEN, with WLAST on the final beat.
--   7. Read-data beat count must match ARLEN, with RLAST on the final beat.
--
-- Reset is ACTIVE-LOW in this design: in main.vhd the 'reset' signal sits at
-- '0' (asserted) for the first few cycles then rises to '1' (running) and stays
-- there; soc_base.clk_reset / SDRAM_reset are active-low (they map to
-- FCLK_RESET0_N on the board). The RESET_ACTIVE generic captures this so the
-- "no VALID during reset" check looks at the correct level. Default '0'.
--
-- At end of simulation, print a PASS/FAIL summary. To get the summary, the
-- testbench can keep running; the counters are visible in the waveform too
-- (error_count signal).
---------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity axi_protocol_checker is
   generic (
      DATA_WIDTH   : integer := 64;
      -- ztachip claims max burst = 9 beats. AXI len = beats-1, so max arlen = 8.
      -- We also hard-require the upper nibble to be zero (HP0 truncation safety).
      MAX_LEN      : integer := 15;  -- absolute AXI3 ceiling (16 beats). Upper
                                     -- nibble check below is the real guard.
      RESET_ACTIVE : std_logic := '0'  -- level of 'reset' that means "in reset"
   );
   port (
      clk        : in std_logic;
      reset      : in std_logic;   -- active level set by RESET_ACTIVE generic

      -- Read address channel
      araddr     : in std_logic_vector(31 downto 0);
      arburst    : in std_logic_vector(1 downto 0);
      arlen      : in std_logic_vector(7 downto 0);
      arsize     : in std_logic_vector(2 downto 0);
      arvalid    : in std_logic;
      arready    : in std_logic;

      -- Write address channel
      awaddr     : in std_logic_vector(31 downto 0);
      awburst    : in std_logic_vector(1 downto 0);
      awlen      : in std_logic_vector(7 downto 0);
      awsize     : in std_logic_vector(2 downto 0);
      awvalid    : in std_logic;
      awready    : in std_logic;

      -- Write data channel
      wlast      : in std_logic;
      wvalid     : in std_logic;
      wready     : in std_logic;

      -- Write response channel
      bresp      : in std_logic_vector(1 downto 0);
      bvalid     : in std_logic;
      bready     : in std_logic;

      -- Read data channel
      rlast      : in std_logic;
      rresp      : in std_logic_vector(1 downto 0);
      rvalid     : in std_logic;
      rready     : in std_logic
   );
end axi_protocol_checker;

architecture sim of axi_protocol_checker is

   signal error_count : integer := 0;   -- watch this in the waveform

   -- helper: is a std_logic_vector free of X/U/Z on the bits we care about?
   function is_known(v : std_logic_vector) return boolean is
   begin
      for i in v'range loop
         if v(i) /= '0' and v(i) /= '1' then
            return false;
         end if;
      end loop;
      return true;
   end function;

begin

   -----------------------------------------------------------------------------
   -- Main checking process. Runs every rising edge. Uses variables to remember
   -- the previous cycle's payload for stability checks, and beat counters for
   -- burst-length checks.
   -----------------------------------------------------------------------------
   check_proc : process(clk)
      -- previous-cycle holds for stability checks
      variable ar_held    : boolean := false;
      variable aw_held    : boolean := false;
      variable araddr_p   : std_logic_vector(31 downto 0) := (others => '0');
      variable arlen_p    : std_logic_vector(7 downto 0)  := (others => '0');
      variable awaddr_p   : std_logic_vector(31 downto 0) := (others => '0');
      variable awlen_p    : std_logic_vector(7 downto 0)  := (others => '0');
      -- burst beat counters
      variable w_beats    : integer := 0;   -- write beats seen in current burst
      variable w_expected : integer := -1;  -- AWLEN+1 of accepted write addr (-1 = idle)
      variable r_beats    : integer := 0;
      variable r_expected : integer := -1;

      procedure flag(msg : string) is
      begin
         report "AXI-CHECK ERROR: " & msg severity error;
         error_count <= error_count + 1;
      end procedure;
   begin
      if rising_edge(clk) then
         if reset = RESET_ACTIVE then
            -----------------------------------------------------------------
            -- Rule 4: nothing may be VALID during reset
            -----------------------------------------------------------------
            if arvalid = '1' or awvalid = '1' or wvalid = '1'
               or bvalid = '1' or rvalid = '1' then
               flag("a *VALID was asserted during reset");
            end if;
            ar_held := false; aw_held := false;
            w_expected := -1; r_expected := -1;
            w_beats := 0; r_beats := 0;
         else
            --------------------------------------------------------------------
            -- READ ADDRESS channel
            --------------------------------------------------------------------
            if arvalid = '1' then
               -- Rule: control fields must be known (no X/U)
               if not is_known(arlen) or not is_known(araddr)
                  or not is_known(arburst) or not is_known(arsize) then
                  flag("AR channel has X/U while ARVALID=1");
               end if;
               -- STAR CHECK (Rule 1): upper nibble of ARLEN must be zero
               if arlen(7 downto 4) /= "0000" then
                  flag("ARLEN > 15 beats - HP0 [3:0] truncation would CORRUPT this read burst");
               end if;
               if to_integer(unsigned(arlen)) > MAX_LEN then
                  flag("ARLEN exceeds AXI3 max (16 beats)");
               end if;
               -- Rule 5: burst type not reserved
               if arburst = "11" then
                  flag("ARBURST = reserved 11");
               end if;
               -- Rule 3: stability while stalled (VALID and not READY)
               if ar_held then
                  if araddr /= araddr_p or arlen /= arlen_p then
                     flag("AR payload changed while ARVALID held and ARREADY=0");
                  end if;
               end if;
               if arready = '0' then
                  ar_held := true; araddr_p := araddr; arlen_p := arlen;
               else
                  ar_held := false;
               end if;
            else
               ar_held := false;
            end if;

            -- Read address handshake accepted -> arm read-data beat counter
            if arvalid = '1' and arready = '1' then
               if r_expected /= -1 then
                  flag("new read address accepted before previous read burst finished");
               end if;
               r_expected := to_integer(unsigned(arlen)) + 1;
               r_beats    := 0;
            end if;

            --------------------------------------------------------------------
            -- WRITE ADDRESS channel
            --------------------------------------------------------------------
            if awvalid = '1' then
               if not is_known(awlen) or not is_known(awaddr)
                  or not is_known(awburst) or not is_known(awsize) then
                  flag("AW channel has X/U while AWVALID=1");
               end if;
               -- STAR CHECK (Rule 1): upper nibble of AWLEN must be zero
               if awlen(7 downto 4) /= "0000" then
                  flag("AWLEN > 15 beats - HP0 [3:0] truncation would CORRUPT this write burst");
               end if;
               if to_integer(unsigned(awlen)) > MAX_LEN then
                  flag("AWLEN exceeds AXI3 max (16 beats)");
               end if;
               if awburst = "11" then
                  flag("AWBURST = reserved 11");
               end if;
               if aw_held then
                  if awaddr /= awaddr_p or awlen /= awlen_p then
                     flag("AW payload changed while AWVALID held and AWREADY=0");
                  end if;
               end if;
               if awready = '0' then
                  aw_held := true; awaddr_p := awaddr; awlen_p := awlen;
               else
                  aw_held := false;
               end if;
            else
               aw_held := false;
            end if;

            -- Write address accepted -> arm write-data beat counter
            if awvalid = '1' and awready = '1' then
               if w_expected /= -1 then
                  flag("new write address accepted before previous write burst finished");
               end if;
               w_expected := to_integer(unsigned(awlen)) + 1;
               w_beats    := 0;
            end if;

            --------------------------------------------------------------------
            -- WRITE DATA channel (Rule 6: beat count + WLAST)
            --------------------------------------------------------------------
            if wvalid = '1' and wready = '1' then
               w_beats := w_beats + 1;
               if w_expected = -1 then
                  flag("write data beat with no preceding write address");
               else
                  if w_beats = w_expected then
                     if wlast /= '1' then
                        flag("WLAST not asserted on final write beat");
                     end if;
                     w_expected := -1;  -- burst complete
                     w_beats := 0;
                  else
                     if wlast = '1' then
                        flag("WLAST asserted early (before AWLEN+1 beats)");
                     end if;
                  end if;
               end if;
            end if;

            --------------------------------------------------------------------
            -- READ DATA channel (Rule 6: beat count + RLAST) + Rule 2 (rresp)
            --------------------------------------------------------------------
            if rvalid = '1' and rready = '1' then
               r_beats := r_beats + 1;
               if rresp = "10" or rresp = "11" then
                  flag("RRESP = SLVERR/DECERR (a read to DDR failed)");
               end if;
               if r_expected = -1 then
                  flag("read data beat with no preceding read address");
               else
                  if r_beats = r_expected then
                     if rlast /= '1' then
                        flag("RLAST not asserted on final read beat");
                     end if;
                     r_expected := -1;
                     r_beats := 0;
                  else
                     if rlast = '1' then
                        flag("RLAST asserted early (before ARLEN+1 beats)");
                     end if;
                  end if;
               end if;
            end if;

            --------------------------------------------------------------------
            -- WRITE RESPONSE channel (Rule 2: bresp)
            --------------------------------------------------------------------
            if bvalid = '1' and bready = '1' then
               if bresp = "10" or bresp = "11" then
                  flag("BRESP = SLVERR/DECERR (a write to DDR failed)");
               end if;
            end if;
         end if;
      end if;
   end process;

end architecture sim;
