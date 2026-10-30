## Nexys A7-100T constraints for the FPGA-only JTAG programmer (rtl/top.sv).
## Pin locations are those of the Digilent master XDC used by
## hw/nexys_a7_jtag_programmer.

## Clock
set_property -dict { PACKAGE_PIN E3  IOSTANDARD LVCMOS33 } [get_ports CLK100MHZ]
create_clock -name sys_clk -period 10.000 -waveform {0 5} [get_ports CLK100MHZ]

## Buttons and switches
set_property -dict { PACKAGE_PIN C12 IOSTANDARD LVCMOS33 } [get_ports CPU_RESETN]
set_property -dict { PACKAGE_PIN N17 IOSTANDARD LVCMOS33 } [get_ports BTNC]
set_property -dict { PACKAGE_PIN M18 IOSTANDARD LVCMOS33 } [get_ports BTNU]
set_property -dict { PACKAGE_PIN J15 IOSTANDARD LVCMOS33 } [get_ports {SW_DIV[0]}]
set_property -dict { PACKAGE_PIN L16 IOSTANDARD LVCMOS33 } [get_ports {SW_DIV[1]}]
set_property -dict { PACKAGE_PIN M13 IOSTANDARD LVCMOS33 } [get_ports {SW_DIV[2]}]
set_property -dict { PACKAGE_PIN U12 IOSTANDARD LVCMOS33 } [get_ports SW_AUTO]
set_property -dict { PACKAGE_PIN U11 IOSTANDARD LVCMOS33 } [get_ports SW_SKIP]
set_property -dict { PACKAGE_PIN V10 IOSTANDARD LVCMOS33 } [get_ports SW_OVR]

## LEDs
set_property -dict { PACKAGE_PIN H17 IOSTANDARD LVCMOS33 } [get_ports {LED[0]}]
set_property -dict { PACKAGE_PIN K15 IOSTANDARD LVCMOS33 } [get_ports {LED[1]}]
set_property -dict { PACKAGE_PIN J13 IOSTANDARD LVCMOS33 } [get_ports {LED[2]}]
set_property -dict { PACKAGE_PIN N14 IOSTANDARD LVCMOS33 } [get_ports {LED[3]}]
set_property -dict { PACKAGE_PIN R18 IOSTANDARD LVCMOS33 } [get_ports {LED[4]}]
set_property -dict { PACKAGE_PIN V17 IOSTANDARD LVCMOS33 } [get_ports {LED[5]}]
set_property -dict { PACKAGE_PIN U17 IOSTANDARD LVCMOS33 } [get_ports {LED[6]}]
set_property -dict { PACKAGE_PIN U16 IOSTANDARD LVCMOS33 } [get_ports {LED[7]}]
set_property -dict { PACKAGE_PIN V16 IOSTANDARD LVCMOS33 } [get_ports {LED[8]}]
set_property -dict { PACKAGE_PIN T15 IOSTANDARD LVCMOS33 } [get_ports {LED[9]}]
set_property -dict { PACKAGE_PIN U14 IOSTANDARD LVCMOS33 } [get_ports {LED[10]}]
set_property -dict { PACKAGE_PIN T16 IOSTANDARD LVCMOS33 } [get_ports {LED[11]}]
set_property -dict { PACKAGE_PIN V15 IOSTANDARD LVCMOS33 } [get_ports {LED[12]}]
set_property -dict { PACKAGE_PIN V14 IOSTANDARD LVCMOS33 } [get_ports {LED[13]}]
set_property -dict { PACKAGE_PIN V12 IOSTANDARD LVCMOS33 } [get_ports {LED[14]}]
set_property -dict { PACKAGE_PIN V11 IOSTANDARD LVCMOS33 } [get_ports {LED[15]}]

## USB-UART (FPGA transmit)
set_property -dict { PACKAGE_PIN D4  IOSTANDARD LVCMOS33 } [get_ports UART_RXD_OUT]

## JTAG master on PMOD JA: JA1 TCK, JA2 TMS, JA3 TDI, JA7 TDO.
## Pull-ups keep TCK/TMS high while the pins are released. Slow slew limits
## ringing on the PMOD cable, which could otherwise double-clock TCK.
set_property -dict { PACKAGE_PIN C17 IOSTANDARD LVCMOS33 DRIVE 8 SLEW SLOW PULLUP TRUE } [get_ports JA_TCK]
set_property -dict { PACKAGE_PIN D18 IOSTANDARD LVCMOS33 DRIVE 8 SLEW SLOW PULLUP TRUE } [get_ports JA_TMS]
set_property -dict { PACKAGE_PIN E18 IOSTANDARD LVCMOS33 DRIVE 8 SLEW SLOW PULLUP TRUE } [get_ports JA_TDI]
set_property -dict { PACKAGE_PIN D17 IOSTANDARD LVCMOS33 PULLUP TRUE } [get_ports JA_TDO]

## Configuration flash (CCLK is driven through STARTUPE2.USRCCLKO).
set_property -dict { PACKAGE_PIN L13 IOSTANDARD LVCMOS33 } [get_ports QSPI_CSN]
set_property -dict { PACKAGE_PIN K17 IOSTANDARD LVCMOS33 } [get_ports QSPI_DQ0]
set_property -dict { PACKAGE_PIN K18 IOSTANDARD LVCMOS33 PULLUP TRUE } [get_ports QSPI_DQ1]
set_property -dict { PACKAGE_PIN L14 IOSTANDARD LVCMOS33 } [get_ports QSPI_DQ2]
set_property -dict { PACKAGE_PIN M14 IOSTANDARD LVCMOS33 } [get_ports QSPI_DQ3]

## The JTAG and flash interfaces are timed in whole system clock cycles from
## registers packed into the IOBs (see jtag_engine.sv, spi_flash_reader.sv),
## so their pad timing is fixed by placement, not by the router.
set_property IOB TRUE [get_ports {JA_TCK JA_TMS JA_TDI JA_TDO QSPI_CSN QSPI_DQ0 QSPI_DQ1}]
set_false_path -to   [get_ports {JA_TCK JA_TMS JA_TDI QSPI_CSN QSPI_DQ0 QSPI_DQ2 QSPI_DQ3 LED[*] UART_RXD_OUT}]
set_false_path -from [get_ports {JA_TDO QSPI_DQ1 CPU_RESETN BTNC BTNU SW_DIV[*] SW_AUTO SW_SKIP SW_OVR}]

## Configuration
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 33 [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
