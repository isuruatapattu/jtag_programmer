# 06 SVF Execution

After the platform and GPIO come up, the player prints the pin line, the SVF blob address and size, and this menu:

```text
Commands:
  p - play embedded SVF over JA JTAG
  d - visible LED SVF demo with no target attached
  t - run one JA output LED test pattern
  r - reset JA outputs low
Input:
```

The command character is echoed. `p` and `P` are the same, and likewise for the other keys. Anything else prints `Unknown command.` and returns to the menu. The loop never exits.

On the ZCU102 the same strings are printed. `JA` in that text is J55; the bit positions do not change. See [02 Hardware setup](02_hardware_setup.md).

## `t`: pin test

This path does not call `libxsvf`. It writes `0x1`, `0x2`, `0x4`, `0x8`, `0xF`, `0x0` to channel 1 with 300 ms between values. On a Nexys A7 that walks JA1, JA2, JA3, JA4, then all four, then off. Use it to prove the output wiring before any SVF runs.

## `d`: slowed SVF, no target

`d` plays a short string compiled into the ELF, not the embedded file:

```svf
TRST OFF;
ENDIR IDLE;
ENDDR IDLE;
STATE RESET;
STATE IDLE;
FREQUENCY 3 HZ;
SIR 6 TDI (09);
SDR 32 TDI (00000000);
RUNTEST 8 TCK;
SIR 6 TDI (14);
SDR 16 TDI (55aa);
STATE RESET;
```

`edge_delay_us` is 100000 and `ignore_tdo` is 1. Each TCK edge stays visible on an LED, TDO is not compared, and no device has to answer. `FREQUENCY 3 HZ` is only text; the delay constant is what sets the pace.

## `r`: idle outputs

`r` sets channel 1 to outputs, channel 2 to inputs, and writes 0. Use it between experiments so TCK, TMS, and TDI are low before the next command. Playback shutdown does the same write.

## `p`: configuration

`p` calls `play_svf_buffer` on `nexys_a7_01_svf_start` with `edge_delay_us = 0` and `ignore_tdo = 0`. Every TDO expectation in the file is enforced. The first one is the IDCODE shift, so a missing or wrong target fails immediately and the large configuration shift never starts.

Phases inside the file, and what the pins do:

| SVF section | JTAG effect |
|---|---|
| `STATE RESET` / `STATE IDLE` | TMS sequences the TAP through Test-Logic-Reset into Run-Test/Idle |
| `SIR 6 TDI (09)` + 32-bit `SDR` | Shift the IDCODE instruction and read 32 bits. Expect `0x03631093` under mask `0x0FFFFFFF` |
| `SIR 6 TDI (0b)` | JPROGRAM |
| `SIR 6 TDI (14)` and the `RUNTEST` pair | Initialization poll, including a 0.1 s wait and 10,000 clocks |
| `SIR 6 TDI (05)` + `SDR 30606304` | Shift the configuration bitstream into the device |
| `config/start` | `JSTART` (`0x0C`) and clocks that complete startup |
| `config/status` | Status read. One bit is checked under mask `0x08000000` |

Status lines on the UART are clipped to 96 characters. The configuration `SDR` is millions of characters, and printing it would dominate the runtime. Errors are clipped the same way.

When the play call returns, the UART shows:

```text
SVF playback finished with rc=<n>
TCK clocks: <n>, TDI bits: <n>, TDO checks: <n>
```

`rc = 0` means `libxsvf` finished the file, including every TDO compare. `rc = -1` means the parser or a compare failed. On the first mismatch the next line is:

```text
TDO mismatches: 1, first at TCK <n> expected <0 or 1> actual <0 or 1>
```

The player also prints `JTAG IDCODE: 0x........` when `libxsvf` reports a device, and `SVF requested JTAG frequency: 10000000 Hz; using GPIO bit-bang speed.` when it hits the `FREQUENCY` command. That frequency is not applied. See [04 JTAG implementation](04_jtag_implementation.md).

## What uses the heap

The configuration `SDR` is one SVF statement. `libxsvf` allocates buffers for the whole statement through `mb_svf_realloc` before the shift starts. The linker reserves 32 MiB for that. If a rebuilt SVF is substantially larger, raise `_HEAP_SIZE` in `src/lscript.ld` and keep the heap inside the DDR region (128 MiB on the Nexys A7).
