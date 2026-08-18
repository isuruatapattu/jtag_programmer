# FPGA JTAG Programmer

This repository contains the FPGA hardware design and embedded software for a
JTAG programmer. The current Nexys A7 implementation uses a MicroBlaze system
and the JA Pmod header as a software-controlled JTAG interface.

The firmware uses `libxsvf` to read an embedded SVF file and drive the target's
TCK, TMS, TDI, and TDO signals. It also provides an LED demonstration mode for
testing the signal path without a connected JTAG target.

## Repository Layout

```text
hw/
  nexys_a7_jtag_programmer/          Vivado hardware project
  nexys_a7_jtag_programmer_2025.01/  For older versions - Includes recreate tcl fiels
  zcu102_jtag_programmer/            ZCU102 project area

sw/
  nexys_a7/ws_20260818/              Nexys A7 Vitis workspace
    app_mb_svf_player/               MicroBlaze SVF player application
    pf_nexys_a7/                     Vitis platform and exported hardware
  zcu102/                            ZCU102 software area
```

## Main Project Files

- Vivado project: `hw/nexys_a7_jtag_programmer/nexys_a7_jtag_programmer.xpr`
- Updated Vivado project: `hw/nexys_a7_jtag_programmer_2025.01/nexys_a7_jtag_programmer.xpr`
- Vitis application: `sw/nexys_a7/ws_20260818/app_mb_svf_player`
- Hardware platform: `sw/nexys_a7/ws_20260818/pf_nexys_a7`

The repository intentionally keeps Vivado project files, Xilinx hardware
platform files (`.xsa`), and FPGA bitstreams (`.bit`) under version control.

## Getting Started

1. Open one of the `.xpr` files in AMD Vivado to inspect or rebuild the Nexys
   A7 hardware design.
2. Open `sw/nexys_a7/ws_20260818` as an AMD Vitis workspace.
3. Build the platform and the `app_mb_svf_player` application.
4. Program the Nexys A7 with the generated bitstream and run the MicroBlaze
   application.

For JTAG wiring, UART commands, build details, and SVF playback instructions,
see the [MicroBlaze SVF Player documentation](sw/nexys_a7/ws_20260818/app_mb_svf_player/README.md).

## Hardware Safety

The Nexys A7 Pmod interface uses 3.3 V logic. Use suitable level shifting when
connecting a target with a different JTAG I/O voltage, and always connect the
grounds of the programmer and target.
