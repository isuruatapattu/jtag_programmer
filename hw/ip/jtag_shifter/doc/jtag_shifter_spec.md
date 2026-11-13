# jtag_shifter - AXI4-Lite JTAG shift engine

`jtag_shifter` drives the Nexys A7 Pmod JA JTAG pins. In bypass mode it passes
the `axi_gpio_0` outputs straight through, so the existing bit-bang firmware
still works. In engine mode it shifts up to 32 bits per AXI write at a
programmable TCK rate.

This document is the reference for the RTL (`rtl/`), the testbench
(`sim/tb_jtag_shifter.sv`) and the driver (`jtag_shifter.h` in
`sw/nexys_a7/app_mb_svf_player_jtag_shifter`).

## Files

| File | Content |
|---|---|
| `rtl/jtag_shifter_top.v` | Verilog-2001 top for the block design module reference, with the `S_AXI` interface attributes |
| `rtl/jtag_shifter_axil.sv` | AXI4-Lite slave, registers, cycle counter, registered pin mux |
| `rtl/jtag_shifter_core.sv` | Bit engine, clock divider, TDO synchronizer |
| `rtl/jtag_shifter_fifo.sv` | First-word-fall-through FIFO in distributed RAM |
| `sim/tb_jtag_shifter.sv` | Self-checking testbench with a TAP model |
| `sim/run_xsim.tcl` | Vivado xsim batch script |

## Ports

| Port | Dir | Width | Description |
|---|---|---|---|
| `s_axi_aclk` | in | 1 | 100 MHz in the Nexys design. All logic runs on this clock. |
| `s_axi_aresetn` | in | 1 | Synchronous, active low |
| `s_axi_*` | | | AXI4-Lite slave `S_AXI`, 8-bit address, 32-bit data. No `PROT` signals. |
| `gpio_bypass_i` | in | 4 | `axi_gpio_0/gpio_io_o` |
| `jtag_i` | in | 4 | Board port `ck_b0` (JA7..JA10). Bit 0 is TDO. |
| `jtag_o` | out | 4 | Board port `ck_a0` (JA1..JA4). Bit 0 TCK, bit 1 TMS, bit 2 TDI, bit 3 spare. |

`jtag_i` takes the whole 4-bit `ck_b0` bus, so the block design does not need
a slice cell. `jtag_o` comes straight from a flip-flop. The constraints pack
that flip-flop into the IOB.

## Register map

The register index is `addr[7:2]`. The block design gives a 64 KiB segment at
`0x44A00000`, so the 256-byte window repeats inside it. Unmapped offsets read
as 0 and ignore writes. Every response is `OKAY`. Writes use the full 32-bit
word; `WSTRB` is ignored, because MicroBlaze always writes with `0xF`.

| Offset | Name | Access | Reset | Fields |
|---|---|---|---|---|
| `0x00` | `CTRL` | R/W | `0x0` | [0] `ENGINE_EN`: 0 = bypass, 1 = engine owns the pins. [1] `FLUSH` (write 1, reads 0): empty both FIFOs and abort the current word. |
| `0x04` | `STATUS` | RO | | [0] `BUSY`: a word is shifting or the TX FIFO is not empty. [1] `TX_FULL`. [2] `RX_EMPTY`. [3] `TX_EMPTY`. [4] `RX_FULL`. [15:8] TX level, saturated at 255. [23:16] RX level, saturated at 255. |
| `0x08` | `CLKDIV` | R/W | `5` | [15:0] TCK half period in clock cycles. 0 acts as 1. TCK = 100 MHz / (2 x CLKDIV). |
| `0x0C` | `CFG` | R/W | `0x1F` | Applied to every later `DATA` write. [4:0] `NBITS-1`. [8] `MODE`. [9] `TMS_LAST`. [10] `CAPTURE`. |
| `0x10` | `DATA` | WO | | A write pushes `{CFG, wdata}` into the TX FIFO. While the FIFO is full, the slave holds the write and returns `BVALID` only after the push. Reads 0. |
| `0x14` | `TDO` | RO | | A read pops one captured word. Bit 0 is the first bit shifted, and bits above `NBITS-1` are 0. Returns 0 without popping when the RX FIFO is empty. |
| `0x18` | `CYCLES` | RO | `0` | Free-running 32-bit counter at the AXI clock |
| `0x1C` | `ID` | RO | | `0x4A534831` ("JSH1") |

### CFG fields

- `MODE = 0`: bit *i* of `DATA` goes to TDI. TMS is 0, except that the last bit has TMS = 1 when `TMS_LAST = 1`.
- `MODE = 1`: bit *i* of `DATA` goes to TMS. TDI keeps its last value, which matches `libxsvf` `tdi = -1`. `TMS_LAST` is ignored.
- `CAPTURE = 1`: after the last bit, the captured TDO bits are pushed into the RX FIFO.

## FIFOs

| FIFO | Width | Depth |
|---|---|---|
| TX | 40 (`CFG` + `DATA`) | 512 |
| RX | 32 | 256 |

If the RX FIFO is full, the engine waits before pushing and stops taking new
words. A `DATA` write that then finds the TX FIFO full would wait forever. The
driver must therefore keep fewer than 256 captured words unread. Each time it
writes a capturing word, it reads `TDO` first if 255 captures are already
outstanding.

## Bit timing

Each bit takes `2 x CLKDIV` cycles:

1. TMS and TDI take the new bit, and TCK goes low, on the same clock edge. TCK stays low for `CLKDIV` cycles.
2. TCK is high for `CLKDIV` cycles. The target samples TMS and TDI on the rising edge.
3. In the cycle that ends the high phase, the engine stores the synchronized TDO for that bit.

TCK idles low. Between words, the low phase is 1 or 2 cycles longer. JTAG is
static, so this has no effect.

TDO goes through a 2-FF synchronizer, and the output mux adds one register
stage. The stored TDO value is therefore the pin level about 3 to 4 cycles
(30 to 40 ns) before TCK falls at the pin. The target drives TDO after the
previous falling edge. The sample is good when
`2 x CLKDIV x 10 ns - 40 ns` exceeds the target clock-to-out delay plus the
wire delay. `CLKDIV = 5` (10 MHz, the rate the SVF asks for) leaves about 60 ns.
Below `CLKDIV = 3`, check the margin on the bench.

## Bypass mode

With `ENGINE_EN = 0`, `jtag_o` follows `gpio_bypass_i` one clock later. With
`ENGINE_EN = 1`, `jtag_o = {0, TDI, TMS, TCK}` from the engine. TDO still
reaches `axi_gpio_0` channel 2 directly from the board port, in both modes.
