# 03 Vivado Design

The Nexys A7 programmer is a MicroBlaze system with DDR2, a UART, a board GPIO for LEDs and switches, and a second GPIO used only as the JTAG port. The figure in [images/vivado/block_design.png](images/vivado/block_design.png) is a documentation drawing of that connectivity. Captured Vivado screenshots can be added beside it; see [images/vivado/README.md](images/vivado/README.md).

## Projects

| Tree | Role |
|---|---|
| `hw/nexys_a7_jtag_programmer/nexys_a7_jtag_programmer.xpr` | Vivado project |
| `hw/nexys_a7_jtag_programmer_2025.01/` | `recreate_project.tcl` and `design_1_2025_2.tcl` |

Open the `.xpr` to inspect or rebuild. To recreate from Tcl, run `recreate_project.tcl` from Vivado with the sibling `nexys_a7_jtag_programmer` tree available. The script's original project path points at that sibling.

The block design recorded in `design_1_2025_2.tcl` uses these IP versions:

| Instance | VLNV |
|---|---|
| `microblaze_0` | `xilinx.com:ip:microblaze:11.0` |
| `mig_7series_0` | `xilinx.com:ip:mig_7series:4.2` |
| `clk_wiz_0` | `xilinx.com:ip:clk_wiz:6.0` |
| `axi_gpio_0` | `xilinx.com:ip:axi_gpio:2.0` |
| `axi_gpio_1` | `xilinx.com:ip:axi_gpio:2.0` |
| `axi_uartlite_0` | `xilinx.com:ip:axi_uartlite:2.0` |
| `axi_smc`, `axi_smc_1` | `xilinx.com:ip:smartconnect:1.0` |
| `mdm_1` | `xilinx.com:ip:mdm:3.2` |
| `rst_clk_wiz_0_100M`, `rst_mig_7series_0_81M` | `xilinx.com:ip:proc_sys_reset:5.0` |
| local memory | LMB v10, LMB BRAM controller, block memory generator |

## Clocks and reset

The board clock port is `clk_100MHz` at 100 MHz. `util_ds_buf_0` buffers it into the clock wizard. The wizard is in board flow with an active-low `reset` tied to the board reset.

- `clk_out1` clocks MicroBlaze, the LMB, both GPIO cores, the UART, and `axi_smc`. The reset block on this clock is named `rst_clk_wiz_0_100M`.
- `clk_out2` is requested at 200 MHz and drives `mig_7series_0/clk_ref_i`.
- The MIG user clock has its own reset, `rst_mig_7series_0_81M`, and `axi_smc_1` sits on that clock domain. MicroBlaze instruction and data cache masters reach DDR through `axi_smc_1`.

## JTAG GPIO

`axi_gpio_0` is the programmer port. Both channels are 4 bits wide. Channel 1 is all outputs (`C_ALL_OUTPUTS 1`) and `gpio_io_o` drives the board port `ck_a0`. Channel 2 is wired from the input port `ck_b0` into `gpio2_io_i`. The firmware also programs the direction registers: channel 1 all outputs, channel 2 all inputs.

`axi_gpio_1` is the board LED and switch interface (`led_16bits`, `dip_switches_16bits`). It is not used by the SVF player.

## Address map

MicroBlaze data space, from `design_1_2025_2.tcl`:

| Peripheral | Base | Range |
|---|---|---|
| LMB BRAM | `0x00000000` | 128 KiB |
| `axi_gpio_0` (JTAG) | `0x40000000` | 64 KiB |
| `axi_gpio_1` (LEDs, switches) | `0x40010000` | 64 KiB |
| `axi_uartlite_0` | `0x40600000` | 64 KiB |
| MIG DDR2 | `0x80000000` | 128 MiB |

Instruction space maps the same LMB and the same DDR window. The linker script places the application, including the embedded SVF, in the DDR window. Vectors stay in the local BRAM. See [04 JTAG implementation](04_jtag_implementation.md).

MicroBlaze is built with the debug module, data-side AXI, and 32 KiB instruction and data caches.

## Bitstream and platform

After implementation:

1. Generate the bitstream.
2. Export the hardware platform (`.xsa`) including the bitstream.
3. Point the Vitis platform `sw/nexys_a7/ws_20260818/pf_nexys_a7` at that export if the hardware changed.
4. Rebuild `app_mb_svf_player` so `xparameters.h` matches the new address map.

A JTAG-only GPIO change that keeps `axi_gpio_0` at `0x40000000` does not require player source edits. A new address does.

## ZCU102

The ZCU102 constraints file defines `jtag_out[3:0]` and `jtag_in[3:0]` on J55. The player looks up `XPAR_XGPIO_0_BASEADDR` and uses channel 1 as the output register and channel 2 as the input register, the same way as on the Nexys A7. The processing system supplies the Cortex-A53 clock, DDR, and the 115200 baud console. Rebuild `pf_zynq` and `app_svf_player` after the block design or the XSA changes.
