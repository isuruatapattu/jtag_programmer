# JTAG Programmer Documentation

This set describes the FPGA JTAG programmer in this repository. A Nexys A7 or a ZCU102 runs embedded software that plays a Serial Vector Format (SVF) file and bit-bangs TCK, TMS, TDI, and TDO on a Pmod connector. The checked-in SVF configures a second Nexys A7 (Artix-7 XC7A100T).

The programmer board and the target board are two different boards. The SVF configures the target. It does not reconfigure the FPGA that is executing the player.

## Read in this order

| Document | What it covers |
|---|---|
| [01 Project overview](01_project_overview.md) | Goal, platforms, and repository map |
| [02 Hardware setup](02_hardware_setup.md) | Boards, power, UART, and JTAG wiring |
| [03 Vivado design](03_vivado_design.md) | Nexys A7 block design, clocks, and address map |
| [04 JTAG implementation](04_jtag_implementation.md) | GPIO bit-bang player and `libxsvf` callbacks |
| [05 SVF generation](05_svf_generation.md) | How the embedded configuration SVF is produced |
| [06 SVF execution](06_svf_execution.md) | UART commands and what playback does |
| [07 Programming a Nexys A7](07_programming_nexys_a7.md) | End-to-end sequence for the target board |
| [08 Results](08_results.md) | Pass criteria and the expected failure with no target |
| [09 Troubleshooting](09_troubleshooting.md) | Checks when playback or configuration fails |

Figures:

- [System architecture](images/system_architecture.png)
- [Wiring](images/wiring_diagram.png)
- [Block diagram](images/vivado/block_design.png)

The Nexys A7 application also has a source-level walkthrough in [`sw/nexys_a7/ws_20260818/app_mb_svf_player/README.md`](../sw/nexys_a7/ws_20260818/app_mb_svf_player/README.md).
