#------------------------------------------------------------------------------
# zynq_ps_bd.tcl
# Block Design TCL for ztachip ZC702 port.
#
# Creates a Zynq PS7 block design that provides:
#   - FCLK_CLK0 : 100 MHz  -> clk_main (ztachip + VexRiscv)  [was 125, lowered to close timing]
#   - FCLK_CLK1 : 200 MHz  -> clk_x2_main  [MUST stay exactly 2x FCLK0 - see soc_base.vhd:1338]
#   - FCLK_CLK2 :  24 MHz  -> clk_camera (OV7670 MCLK)
#   - FCLK_CLK3 :  25 MHz  -> clk_vga
#   - FCLK_RESET0_N        -> active-low PL reset
#   - S_AXI_HP0            -> 64-bit AXI3 slave (ztachip DMA to PS DDR3)
#
# PREREQUISITES:
#   ZC702 board files must be installed in Vivado.
#   If not installed, download from:
#     https://github.com/Xilinx/XilinxBoardStore
#   and copy to <Vivado_install>/data/boards/board_files/
#------------------------------------------------------------------------------

proc create_zynq_bd {} {

    create_bd_design "zynq_system"
    current_bd_design zynq_system

    #--------------------------------------------------------------------------
    # Instantiate PS7
    #--------------------------------------------------------------------------
    create_bd_cell -type ip \
        -vlnv xilinx.com:ip:processing_system7:5.5 \
        processing_system7_0

    #--------------------------------------------------------------------------
    # Apply ZC702 board preset.
    # This sets DDR3 timing, MIO banking, and UART/Ethernet/SD MIO assignments.
    # If board files are missing, remove the apply_bd_automation call below and
    # manually set PCW_DDR_* parameters for your specific DDR3 device.
    #--------------------------------------------------------------------------
    apply_bd_automation \
        -rule xilinx.com:bd_rule:processing_system7 \
        -config { \
            make_external   "FIXED_IO, DDR" \
            apply_board_preset "1" \
            Master "Disable" \
            Slave  "Disable" \
        } \
        [get_bd_cells processing_system7_0]

    #--------------------------------------------------------------------------
    # PS7 additional configuration
    #   HP0  : enabled, 64-bit data width (matches exmem_data_width_c=64)
    #   FCLK : four fabric clocks for PL
    #   UART1: MIO48/49 -> USB-UART chip on ZC702 (for ARM console)
    #--------------------------------------------------------------------------
    set_property -dict [list \
        CONFIG.PCW_USE_S_AXI_HP0        {1}   \
        CONFIG.PCW_S_AXI_HP0_DATA_WIDTH {64}  \
        CONFIG.PCW_USE_M_AXI_GP0        {0}   \
        CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {90} \
        CONFIG.PCW_FPGA1_PERIPHERAL_FREQMHZ {180} \
        CONFIG.PCW_FPGA2_PERIPHERAL_FREQMHZ {24}  \
        CONFIG.PCW_FPGA3_PERIPHERAL_FREQMHZ {25}  \
        CONFIG.PCW_EN_CLK0_PORT  {1} \
        CONFIG.PCW_EN_CLK1_PORT  {1} \
        CONFIG.PCW_EN_CLK2_PORT  {1} \
        CONFIG.PCW_EN_CLK3_PORT  {1} \
        CONFIG.PCW_EN_RST0_PORT  {1} \
        CONFIG.PCW_UART1_PERIPHERAL_ENABLE {1} \
        CONFIG.PCW_UART1_UART1_IO {MIO 48 .. 49} \
    ] [get_bd_cells processing_system7_0]

    #--------------------------------------------------------------------------
    # Expose FCLK clock outputs as BD ports
    #--------------------------------------------------------------------------
    create_bd_port -dir O -type clk FCLK_CLK0
    create_bd_port -dir O -type clk FCLK_CLK1
    create_bd_port -dir O -type clk FCLK_CLK2
    create_bd_port -dir O -type clk FCLK_CLK3
    create_bd_port -dir O -type rst FCLK_RESET0_N

    connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0]     [get_bd_ports FCLK_CLK0]
    connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK1]     [get_bd_ports FCLK_CLK1]
    connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK2]     [get_bd_ports FCLK_CLK2]
    connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK3]     [get_bd_ports FCLK_CLK3]
    connect_bd_net [get_bd_pins processing_system7_0/FCLK_RESET0_N] [get_bd_ports FCLK_RESET0_N]

    #--------------------------------------------------------------------------
    # Expose S_AXI_HP0 as AXI3 slave BD interface port
    # (AXI3: 4-bit ARLEN/AWLEN, max 16 bursts per transaction)
    # ztachip max burst = 9 so AXI3 is sufficient - no protocol converter needed.
    #--------------------------------------------------------------------------
    create_bd_intf_port \
        -mode Slave \
        -vlnv xilinx.com:interface:aximm_rtl:1.0 \
        S_AXI_HP0
    set_property -dict [list \
        CONFIG.PROTOCOL   {AXI3} \
        CONFIG.DATA_WIDTH {64}   \
        CONFIG.ADDR_WIDTH {32}   \
        CONFIG.ID_WIDTH   {6}    \
    ] [get_bd_intf_ports S_AXI_HP0]

    connect_bd_intf_net \
        [get_bd_intf_ports S_AXI_HP0] \
        [get_bd_intf_pins processing_system7_0/S_AXI_HP0]

    # HP0 clock (PL side)
    create_bd_port -dir I -type clk S_AXI_HP0_ACLK
    connect_bd_net \
        [get_bd_ports S_AXI_HP0_ACLK] \
        [get_bd_pins processing_system7_0/S_AXI_HP0_ACLK]

    #--------------------------------------------------------------------------
    # Assign PS DDR address range to HP0 slave segment.
    # This maps 0x00000000-0x3FFFFFFF (1 GB PS DDR) into the HP0 address space
    # so ztachip DMA transactions reach PS DDR correctly.
    #--------------------------------------------------------------------------
    assign_bd_address [get_bd_addr_segs {processing_system7_0/S_AXI_HP0/HP0_DDR_LOWOCM}]

    #--------------------------------------------------------------------------
    # Validate and save
    #--------------------------------------------------------------------------
    validate_bd_design
    save_bd_design
    puts "INFO: zynq_system block design created successfully."
}

create_zynq_bd
