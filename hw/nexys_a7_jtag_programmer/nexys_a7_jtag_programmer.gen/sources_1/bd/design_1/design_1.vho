-- Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
-- Copyright 2022-2026 Advanced Micro Devices, Inc. All Rights Reserved.
-- -------------------------------------------------------------------------------
-- This file contains confidential and proprietary information
-- of AMD and is protected under U.S. and international copyright
-- and other intellectual property laws.
--
-- DISCLAIMER
-- This disclaimer is not a license and does not grant any
-- rights to the materials distributed herewith. Except as
-- otherwise provided in a valid license issued to you by
-- AMD, and to the maximum extent permitted by applicable
-- law: (1) THESE MATERIALS ARE MADE AVAILABLE "AS IS" AND
-- WITH ALL FAULTS, AND AMD HEREBY DISCLAIMS ALL WARRANTIES
-- AND CONDITIONS, EXPRESS, IMPLIED, OR STATUTORY, INCLUDING
-- BUT NOT LIMITED TO WARRANTIES OF MERCHANTABILITY, NON-
-- INFRINGEMENT, OR FITNESS FOR ANY PARTICULAR PURPOSE; and
-- (2) AMD shall not be liable (whether in contract or tort,
-- including negligence, or under any other theory of
-- liability) for any loss or damage of any kind or nature
-- related to, arising under or in connection with these
-- materials, including for any direct, or any indirect,
-- special, incidental, or consequential loss or damage
-- (including loss of data, profits, goodwill, or any type of
-- loss or damage suffered as a result of any action brought
-- by a third party) even if such damage or loss was
-- reasonably foreseeable or AMD had been advised of the
-- possibility of the same.
--
-- CRITICAL APPLICATIONS
-- AMD products are not designed or intended to be fail-
-- safe, or for use in any application requiring fail-safe
-- performance, such as life-support or safety devices or
-- systems, Class III medical devices, nuclear facilities,
-- applications related to the deployment of airbags, or any
-- other applications that could lead to death, personal
-- injury, or severe property or environmental damage
-- (individually and collectively, "Critical
-- Applications"). Customer assumes the sole risk and
-- liability of any use of AMD products in Critical
-- Applications, subject only to applicable laws and
-- regulations governing limitations on product liability.
--
-- THIS COPYRIGHT NOTICE AND DISCLAIMER MUST BE RETAINED AS
-- PART OF THIS FILE AT ALL TIMES.
--
-- DO NOT MODIFY THIS FILE.

-- MODULE VLNV: amd.com:blockdesign:design_1:1.0

-- The following code must appear in the VHDL architecture header.

-- COMP_TAG     ------ Begin cut for COMPONENT Declaration ------
COMPONENT design_1
  PORT (
    ddr2_sdram_dq : INOUT STD_LOGIC_VECTOR(15 DOWNTO 0);
    ddr2_sdram_dqs_p : INOUT STD_LOGIC_VECTOR(1 DOWNTO 0);
    ddr2_sdram_dqs_n : INOUT STD_LOGIC_VECTOR(1 DOWNTO 0);
    ddr2_sdram_addr : OUT STD_LOGIC_VECTOR(12 DOWNTO 0);
    ddr2_sdram_ba : OUT STD_LOGIC_VECTOR(2 DOWNTO 0);
    ddr2_sdram_ras_n : OUT STD_LOGIC;
    ddr2_sdram_cas_n : OUT STD_LOGIC;
    ddr2_sdram_we_n : OUT STD_LOGIC;
    ddr2_sdram_ck_p : OUT STD_LOGIC_VECTOR(0 DOWNTO 0);
    ddr2_sdram_ck_n : OUT STD_LOGIC_VECTOR(0 DOWNTO 0);
    ddr2_sdram_cke : OUT STD_LOGIC_VECTOR(0 DOWNTO 0);
    ddr2_sdram_cs_n : OUT STD_LOGIC_VECTOR(0 DOWNTO 0);
    ddr2_sdram_dm : OUT STD_LOGIC_VECTOR(1 DOWNTO 0);
    ddr2_sdram_odt : OUT STD_LOGIC_VECTOR(0 DOWNTO 0);
    usb_uart_rxd : IN STD_LOGIC;
    usb_uart_txd : OUT STD_LOGIC;
    led_16bits_tri_o : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
    dip_switches_16bits_0_tri_i : IN STD_LOGIC_VECTOR(15 DOWNTO 0);
    ck_a0 : OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
    reset : IN STD_LOGIC;
    ck_b0 : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
    clk_100MHz : IN STD_LOGIC
  );
END COMPONENT;
-- COMP_TAG_END ------  End cut for COMPONENT Declaration  ------

-- The following code must appear in the VHDL architecture
-- body. Substitute your own instance name and net names.

-- INST_TAG     ------ Begin cut for INSTANTIATION Template ------
your_instance_name : design_1
  PORT MAP (
    ddr2_sdram_dq => ddr2_sdram_dq,
    ddr2_sdram_dqs_p => ddr2_sdram_dqs_p,
    ddr2_sdram_dqs_n => ddr2_sdram_dqs_n,
    ddr2_sdram_addr => ddr2_sdram_addr,
    ddr2_sdram_ba => ddr2_sdram_ba,
    ddr2_sdram_ras_n => ddr2_sdram_ras_n,
    ddr2_sdram_cas_n => ddr2_sdram_cas_n,
    ddr2_sdram_we_n => ddr2_sdram_we_n,
    ddr2_sdram_ck_p => ddr2_sdram_ck_p,
    ddr2_sdram_ck_n => ddr2_sdram_ck_n,
    ddr2_sdram_cke => ddr2_sdram_cke,
    ddr2_sdram_cs_n => ddr2_sdram_cs_n,
    ddr2_sdram_dm => ddr2_sdram_dm,
    ddr2_sdram_odt => ddr2_sdram_odt,
    usb_uart_rxd => usb_uart_rxd,
    usb_uart_txd => usb_uart_txd,
    led_16bits_tri_o => led_16bits_tri_o,
    dip_switches_16bits_0_tri_i => dip_switches_16bits_0_tri_i,
    ck_a0 => ck_a0,
    reset => reset,
    ck_b0 => ck_b0,
    clk_100MHz => clk_100MHz
  );
-- INST_TAG_END ------  End cut for INSTANTIATION Template  ------

-- You must compile the wrapper file design_1.vhd when simulating
-- the module, design_1. When compiling the wrapper file, be sure to
-- reference the VHDL simulation library.
