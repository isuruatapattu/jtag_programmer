# 09 Troubleshooting

Work in this order. Most `p` failures are the IDCODE compare, and the earlier commands separate a wiring fault from a target fault.

## 1. Console

| Symptom | What to check |
|---|---|
| No banner | Wrong serial port, or the ELF is not running. Nexys A7 USB-UART follows the AXI UART Lite baud (board preset 9600). ZCU102 PS UART is 115200. |
| `JA GPIO init failed` and the CPU sits in a loop | `XPAR_XGPIO_0_BASEADDR` does not match the hardware. Rebuild the Vitis platform from the current XSA. |
| Blob size is not 7,712,741 | The linked SVF is not `assets/nexys_a7_01.svf`. Rebuild after replacing the asset. CMake generates `svf_blob.generated.S` in the build directory. |
| Menu prints `JA1=TCK` on the ZCU102 | Expected. That string is compiled in. Use J55.1 / J55.3 / J55.5 / J55.7. |

## 2. Outputs (`t`, then `d`)

| Symptom | What to check |
|---|---|
| `t` does not move the LEDs | Resistor and ground, pin (JA1–JA4 or J55.1 / J55.3 / J55.5 / J55.2), and that the programmer bitstream is the JTAG design rather than a different project. |
| `d` is silent on the pins but the UART finishes | LEDs still on the wrong pins, or the delay is being watched on TDO. TCK is JA1 / J55.1. |
| `d` returns `rc=-1` | The failure is in the short built-in SVF or the parser, not in the target. TDO is ignored in this mode, so an open TDO pin is not the cause. |

## 3. Target wiring (`p`)

`TDO mismatch` on the first data shift means the 32 bits sampled on TDO were not the masked IDCODE.

| Check | Why it fails the compare |
|---|---|
| Target power | JP3 and the barrel jack. If J6 is the only supply and you unplugged it, the FPGA is off and TDO is undriven. |
| PROG USB still plugged into the target | J6's USB-JTAG circuit shares TCK, TMS, and TDI with J10. Unplug J6 for the run. |
| TDI and TDO swapped | The programmer never sees the device's shift output. |
| TDO on JA4 / J55.2 instead of JA7 / J55.7 | Those pins are outputs. TDO is the channel-2 bit 0 input. |
| Ground missing | The two boards have no common reference. Sampled TDO is noise. |
| 3.3 V pins tied together | Not required, and it fights the supplies. Remove that wire. |
| Target is not an XC7A100T | The SVF expects `0x03631093`. Another part fails even with perfect wiring. |
| Extra devices on the chain | `HIR`/`TIR`/`HDR`/`TDR` are 0. Only the Artix-7 may sit between TDI and TDO. |
| JP1 left on QSPI, microSD, or USB | JTAG configuration can still start, but another source can overwrite it afterward. Use the JTAG position. |
| LEDs left on TCK, TMS, or TDI | Extra load on the edges. Remove them before `p`. |

The mismatch line gives the TCK count and the two bit values. `expected 1 actual 0` on an early clock, with a target that is powered and grounded, is still a wiring or chain problem, not a bad bitstream. The configuration shift has not started yet.

A mismatch after a long run, with a large TCK count, means IDCODE and the init poll passed and a later compare failed. Check that the SVF was generated for `xc7a100tcsg324-1`, that the target stayed powered for the whole shift, and that nothing else drove TMS or TCK partway through. Then regenerate the SVF if the bitstream changed. See [05 SVF generation](05_svf_generation.md).

## 4. Build and memory

| Symptom | What to check |
|---|---|
| Link fails looking for `mb-size` | Prepend `C:\AMDDesignTools\2025.2\Vitis\gnu\microblaze\nt\bin` to `PATH` and rebuild. |
| Playback dies inside the big `SDR` with an allocation error | `_HEAP_SIZE` in `src/lscript.ld` is no longer large enough for that SVF. The design uses 32 MiB. |
| `warning: missing initializer for field 'has_tdo_data'` | Comes from upstream `libxsvf/svf.c`. The field is zero-initialized and the link still succeeds. |
| Player runs and immediately faults | The ELF was linked for the wrong memory map. The Nexys A7 script uses DDR at `0x80000000`. The ZCU102 script uses `psu_ddr_0` at `0x0`. |

## 5. After a good `rc`

`rc=0` with DONE off means the status compare in the SVF was satisfied and the board indicator was not. Confirm you are looking at the target DONE LED (callout 6), not an LED on the programmer, and that PROG was not pressed. If DONE lights and then goes out, JP1 is loading another image or PROG was pressed.

`rc=0` with the wrong design running means the ELF still contains an older SVF. Compare the printed blob size with 7,712,741 and rebuild against the asset you just generated.
