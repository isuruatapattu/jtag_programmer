# 01 Project Overview

The programmer turns a general-purpose FPGA board into a JTAG master. Software parses an SVF file with [`libxsvf`](https://github.com/cliffordwolf/libxsvf) and drives the target Test Access Port (TAP) through an AXI GPIO block. There is no JTAG cable IP and no vendor programming pod in the data path.

```text
Host PC                         Programmer board                    Target board
Vivado  -- bitstream / SVF -->  CPU + DDR + AXI GPIO  -- TCK  -->   Nexys A7 J10
Vitis   -- ELF with SVF ----->  UART console          -- TMS  -->   XC7A100T TAP
                                Pmod pins             -- TDI  -->
                                                      <-- TDO --
                                                      --- GND ---
```

See [system_architecture.png](images/system_architecture.png).

## What the current SVF does

`assets/nexys_a7_01.svf` is a Vivado configuration SVF for one device:

- Instruction length is 6 bits, which matches a 7-series TAP.
- The chain padding is zero (`HIR 0`, `TIR 0`, `HDR 0`, `TDR 0`), so the Artix-7 must be the only device on the scan chain.
- The IDCODE check expects `0x03631093` with mask `0x0FFFFFFF`. That is the XC7A100T on a Nexys A7-100T. The mask ignores the 4-bit revision field.
- The configuration payload is one data shift of 30,606,304 bits, followed by the startup and status checks Vivado emits.

Both applications embed that file at build time. Changing the bitstream means generating a new SVF, replacing the asset, and rebuilding the ELF. See [05 SVF generation](05_svf_generation.md).

## Two programmer platforms

| | Nexys A7 programmer | ZCU102 programmer |
|---|---|---|
| Project | `hw/nexys_a7_jtag_programmer` and `hw/nexys_a7_jtag_programmer_2025.01` | `hw/zcu102_jtag_programmer` |
| CPU | MicroBlaze | Cortex-A53, standalone domain |
| Application | `sw/nexys_a7/ws_20260818/app_mb_svf_player` | `sw/zcu102/ws_20260819/app_svf_player` |
| JTAG connector | Pmod JA | Pmod J55 |
| Program memory | 128 MiB DDR2 at `0x80000000` | PS DDR (`psu_ddr_0`) |
| Console | Board USB-UART (AXI UART Lite) | PS UART, 115200 baud |

The player source is the same design on both platforms: dual-channel AXI GPIO, channel 1 outputs, channel 2 inputs, and the same bit assignment (bit 0 TCK, bit 1 TMS, bit 2 TDI, input bit 0 TDO). The ZCU102 binary still prints the Nexys pin names (`JA1`, `JA2`, `JA3`, `JA7`). On that board those names mean the J55 pins in [02 Hardware setup](02_hardware_setup.md).

## Repository map

```text
hw/nexys_a7_jtag_programmer/             Vivado project
hw/nexys_a7_jtag_programmer_2025.01/     Recreate Tcl for the 2025.1 flow
hw/zcu102_jtag_programmer/               ZCU102 project and J55 constraints
sw/nexys_a7/ws_20260818/                 Vitis workspace, platform, MicroBlaze app
sw/zcu102/ws_20260819/                   Vitis workspace and Cortex-A53 app
docs/                                    This documentation
```

Vivado project files (`.xpr`), exported hardware (`.xsa`), and bitstreams (`.bit`) are kept in version control on purpose. Generated implementation directories, Vitis build trees, and ELF files are ignored.

## Operating modes

The UART menu is the whole user interface:

| Key | Mode | Target required |
|---|---|---|
| `t` | Walk a 4-bit pattern on the output pins | No |
| `d` | Short SVF, slowed to about 100 ms per edge, TDO ignored | No |
| `p` | Embedded configuration SVF at GPIO speed, TDO checked | Yes |
| `r` | Drive the outputs low | No |

`t` and `d` are the bring-up path. `p` is the programming path. Details are in [06 SVF execution](06_svf_execution.md) and [07 Programming a Nexys A7](07_programming_nexys_a7.md).

## Voltage

Pmod JA on the Nexys A7 and J55 in this ZCU102 design are LVCMOS33. The Nexys A7 JTAG bank is 3.3 V, so a Nexys-to-Nexys or ZCU102-to-Nexys connection does not need level shifters. Any other target voltage does. Always connect the grounds. Never connect the programmer's 3.3 V pin to the target.
