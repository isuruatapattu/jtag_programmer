# nexys_a7_jtag_programmer_jtag_shifter

This is a copy of `hw/nexys_a7_jtag_programmer` with one change: a hardware JTAG shifter (`hw/ip/jtag_shifter`) sits between the MicroBlaze and the JA pins. The MicroBlaze writes up to 32 TDI or TMS bits per AXI write, and the shifter clocks them out. The original project is not modified.

## What changed from `nexys_a7_jtag_programmer`

| Item | Change |
|---|---|
| `axi_smc` | `NUM_MI` 3 -> 4; `M03_AXI` drives `jtag_shifter/S_AXI` |
| `jtag_shifter` | New module-reference cell (`jtag_shifter_top`), clocked by `microblaze_0_Clk`, reset by `rst_clk_wiz_0_100M_peripheral_aresetn` |
| `ck_a0` (JA1..JA4) | Now driven by `jtag_shifter/jtag_o`. `axi_gpio_0/gpio_io_o` goes to `jtag_shifter/gpio_bypass_i` |
| `ck_b0` (JA7..JA10) | Still drives `axi_gpio_0/gpio2_io_i`, and also `jtag_shifter/jtag_i` (bit 0 = TDO) |
| XDC | `IOB TRUE` on `ck_a0[*]` so the registered pin mux packs into the I/O flops |

After reset the shifter is in bypass, so the JA pins follow `axi_gpio_0` exactly as in the original design. The existing apps (`sw/nexys_a7/app_mb_svf_player` and others) behave the same on this bitstream.

## Address map

| Peripheral | Base | Range |
|---|---|---|
| `axi_gpio_0` (JA) | `0x4000_0000` | 64 KiB |
| `jtag_shifter` | `0x44A0_0000` | 64 KiB |
| MIG (DDR2) | `0x8000_0000` | unchanged |

For the shifter registers, see `hw/ip/jtag_shifter/doc/jtag_shifter_spec.md`. The `ID` register at `+0x1C` reads `0x4A534831` ("JSH1").

## Build

On the Vivado 2025.1 host:

```sh
# 1. Simulate the IP (prints "TB RESULT: PASS")
cd hw/ip/jtag_shifter/sim
vivado -mode batch -source run_xsim.tcl

#    or, in QuestaSim, from hw/ip/jtag_shifter:
vsim -c -do sim/run_questa.tcl    # batch, exit 0 only on TB RESULT: PASS
vsim -do sim/run_questa.tcl       # GUI; sim/wave.do groups pins, TAP, AXI, engine, FIFOs

# 2. Create this project from nexys_a7_jtag_programmer, edit the block design,
#    build the bitstream, check timing (fails if WNS < 0) and export the XSA
cd hw/nexys_a7_jtag_programmer_jtag_shifter
vivado -mode batch -source create_project.tcl
#    or only create/edit the project:
vivado -mode batch -source create_project.tcl -tclargs -nobuild
```

Outputs in this directory:
- `nexys_a7_jtag_programmer_jtag_shifter.xpr`
- `timing_summary.rpt`
- `design_1_wrapper.xsa` (fixed platform, bitstream included)

If you run the script again, it reopens the new project and skips the block design edits that are already done.

Next, build the software with `sw/nexys_a7/create_platform_jtag_shifter.py` (see `sw/nexys_a7/app_mb_svf_player_jtag_shifter/README.md`).
