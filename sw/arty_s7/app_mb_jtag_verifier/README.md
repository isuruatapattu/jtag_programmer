# MicroBlaze JTAG Verifier

This application is the counterpart to the ZCU102 SVF player in `sw/zcu102/app_svf_player/svf_player.c`. The player turns ZCU102 PMOD header J55 into a software JTAG master and generates TCK, TMS, and TDI. This application runs on an Arty S7-25, captures those signals, acts as the JTAG target, and checks that what arrived on the wires matches the SVF file.

It is the Arty S7 port of `sw/nexys_a7/app_mb_jtag_verifier`. The firmware is the same. The Vitis component stays bound to `sw/arty_s7/platform`, domain `standalone_microblaze_0`. In this testing phase the same SVF file is embedded into the player and the verifier.

## Core Idea

The verifier does not implement a JTAG TAP state machine of its own and it does not write a second SVF parser. It runs the *same* `libxsvf_play()` over the *same* SVF bytes as the player, but its `pulse_tck` callback is inverted:

| | ZCU102 `app_svf_player` | Arty S7 `app_mb_jtag_verifier` |
|---|---|---|
| TCK | drives the pulse | waits for the pulse |
| TMS | drives the expected value | samples and compares |
| TDI | drives the expected value | samples and compares |
| TDO | samples and compares | drives the expected value |

Because `libxsvf` is deterministic, both instances walk the SVF file in lockstep and produce the same per-clock sequence. On every JTAG clock the verifier's callback receives exactly what the player's callback receives:

- `tms` — the value the player should be driving on TMS
- `tdi` — the value the player should be driving on TDI, or `-1` if TDI is a don't-care
- `tdo` — the value the SVF says the *target* should return, or `-1` if the SVF does not check TDO on this bit

So the verifier compares `tms`/`tdi` against the pins and drives `tdo` onto the pins. Driving TDO is what lets the player's own `TDO (...)` checks pass, which closes the loop and proves the return path as well.

## Platform Parameters

The application takes addresses from the Arty BSP `xparameters.h`. It does not use the Nexys linker memory map.

| Resource | Arty S7 value | How the firmware uses it |
|---|---|---|
| `axi_gpio_0` | `XPAR_XGPIO_0_BASEADDR` = `0x40000000`, dual, 4 bits per channel | `XGpio_LookupConfig`. Channel 1 is the output port. Channel 2 is the input port. |
| Second GPIO | not present (`XPAR_XGPIO_NUM_INSTANCES` is 1) | unused. The Nexys LED/DIP GPIO at `0x40010000` does not exist here. |
| UART | `axi_uartlite_0` at `0x40600000`, 9600 baud, 8 data bits, no parity | BSP `inbyte` / `outbyte`. There is no NS16550, so `platform.c` does not program a baud rate. |
| MIG DDR | `0x80000000`–`0x8FFFFFFF` (256 MiB) | code, `.rodata` SVF blob, 32 MiB heap, 16 KiB stack |
| LMB BRAM | `0x0`–`0xFFFF` (64 KiB) | reset and exception vectors only. The linker local region stays `ORIGIN = 0x50`, `LENGTH = 0xFFB0`. |
| CPU clock | `99997538` Hz | `usleep()` through xiltimer, which divides this clock by 4. There is no timer IP and no interrupt controller. |
| Part | Spartan-7 `7s25` | board identity only. The firmware does not branch on `XPAR_DEVICE_ID`. |

`axi_gpio_0` channel 1 is hard-wired as all outputs. Channel 2 is hard-wired as all inputs. The firmware still calls `XGpio_SetDataDirection` so the source stays the same as the Nexys verifier.

The GPIO poll limits are unchanged. This clock is about 0.0025% below the 100 MHz Nexys clock, which is inside the margin of a software poll loop. The app is built at `-O2` so that loop keeps the same speed class as the Nexys build. `-O0` would miss edges the Nexys build can follow.

## Hardware Connections

Both designs use a dual-channel AXI GPIO: channel 1 is the 4-bit output port and channel 2 is the 4-bit input port. The bit assignments in `svf_player.c` and `jtag_verifier.c` match that programming model.

On the ZCU102 (`hw/zcu102_jtag_programmer`, `jtag_pins.xdc`), `jtag_out[0..2]` is GPIO channel 1 and `jtag_in[0]` is GPIO channel 2 bit 0:

| Signal | J55 pin | FPGA pin | GPIO |
|---|---|---|---|
| TCK | J55.1 | A20 | channel 1 bit 0, output |
| TMS | J55.3 | B20 | channel 1 bit 1, output |
| TDI | J55.5 | A22 | channel 1 bit 2, output |
| TDO | J55.7 | A21 | channel 2 bit 0, input |

J55.2, J55.4, J55.6, and J55.8 are constrained but unused. Leave them open.

On the Arty S7 the same bits are `axi_gpio_0`. The UART text keeps the JA names from the Nexys verifier. Those names are the logical header positions, not package pins from the Nexys XDC. Package pins live in the Arty constraints, which are outside this software tree. The BSP only records the GPIO as a custom 4-bit dual port.

| Signal | Menu name | GPIO |
|---|---|---|
| TCK | JA7 | channel 2 bit 0, input |
| TMS | JA8 | channel 2 bit 1, input |
| TDI | JA9 | channel 2 bit 2, input |
| TDO | JA1 | channel 1 bit 0, output |

Channel 2 bit 3 is unused. Channel 1 bits 1, 2, and 3 stay low.

Wire the headers point to point using that bit map. Do not use a straight ribbon cable: the J55 and JA numberings do not line up, and several unused pins are driven.

| Signal | ZCU102 pin | Direction | Arty S7 pin |
|---|---|---|---|
| TCK | J55.1 | player to verifier | JA7 |
| TMS | J55.3 | player to verifier | JA8 |
| TDI | J55.5 | player to verifier | JA9 |
| TDO | J55.7 | verifier to player | JA1 |
| GND | J55.9 or J55.10 | common | header ground |

```text
ZCU102 J55.1  ------->  Arty JA7     TCK
ZCU102 J55.3  ------->  Arty JA8     TMS
ZCU102 J55.5  ------->  Arty JA9     TDI
ZCU102 J55.7  <-------  Arty JA1     TDO
ZCU102 GND    <------>  Arty GND
```

J55 is on ZCU102 bank 47, powered by `VADJ_FPGA`. The ZCU102 constraints use `LVCMOS33`. Set `VADJ_FPGA` to 3.3 V before connecting the boards, and confirm the Arty header bank is also 3.3 V. The Arty drives TDO into J55.7.

Xilinx labels J55 as pin 1, 3, 5, 7 down the signal column, with 2, 4, 6, 8 beside them and ground on pins 9 and 10. Digilent labels a Pmod header as pins 1–4 on the top row and 7–10 on the bottom row. The incoming JTAG signals are the bottom row: JA7, JA8, JA9.

## Clock Speed Is A Hard Constraint

The verifier detects TCK edges by polling the AXI GPIO input register from C. It needs real time between the player's falling edge and the player's TDO sample in order to place the TDO bit on the wire.

The ZCU102 player's commands are:

| Player command | SVF | Edge delay | TDO check | Use with the verifier |
|---|---|---|---|---|
| `d` | LED demo SVF | 100 ms | ignored | yes, first bring-up |
| `p` | embedded `nexys_a7_01.svf` | none | enabled | no, clocks faster than the poll loop |

`d` is the command that can be checked end to end today. The LED demo SVF has no `TDO (...)` fields, and the player ignores TDO anyway, so this validates TCK, TMS, and TDI only. The 100 ms edge delay leaves a large timing margin.

`p` bit-bangs with `edge_delay_us = 0`. That is too fast for this polling verifier. The player also has no slow playback command for the embedded file, and it does not contain the verifier's loop-test SVF, so the verifier's `l` and `v` commands have nothing on the ZCU102 to pair with yet.

The embedded SVF contains a single `SDR 30606304` command, so a full-file run is roughly 30.6 million JTAG clocks. Use the verifier's `c` command to print the expected clock count before planning that run. The file keeps the name `nexys_a7_01.svf`, and the symbols stay `nexys_a7_01_svf_start` / `nexys_a7_01_svf_end`, so the bytes stay identical to the player and the Nexys verifier.

## Test Sequence

Order matters. The verifier must be armed and polling before the player starts clocking.

1. Set ZCU102 `VADJ_FPGA` to 3.3 V, then wire the boards as above, including ground.
2. Open a UART terminal to each board. The Arty UART Lite is 9600 baud.
3. On the verifier, run `i` and confirm `TCK(JA7)=0`. If TCK reads 1 while the player is idle, the wiring is wrong.
4. On the verifier, press `d`. It prints `Armed. Waiting for TCK on JA7.` and starts polling.
5. On the player, press `d`.
6. The player prints its playback summary. The verifier prints its report.

A good LED-demo run has zero TMS and TDI mismatches and zero TCK edge timeouts. The TDO drive count stays at zero because the demo SVF has no TDO fields. Exact clock counts depend on how `libxsvf` sequences the TAP; confirm them with the verifier's `c` dry run only for the embedded file. The LED demo is a short built-in string, so its clock count is whatever `d` reports.

## UART Commands

```text
Commands:
  v - verify captured JTAG against the embedded SVF
  l - verify against the short loop-test SVF
  d - verify against the LED demo SVF
  c - dry run the embedded SVF to count expected clocks
  m - monitor raw TCK/TMS/TDI without comparing
  i - print JA input levels
  t - blink the TDO output on JA1
  r - reset JA outputs low
Input:
```

### `d`: LED Demo SVF

Pairs with the ZCU102 player's `d` command. This is the bring-up test. The demo SVF has no TDO fields, so it validates TCK, TMS, and TDI capture only.

### `l`: Loop-Test SVF

The loop-test SVF is short and contains `TDO (...) MASK (...)` fields, so a pass would exercise all four JTAG wires. The ZCU102 player does not embed this SVF and has no matching command, so `l` cannot be run against the current player.

### `v`: Embedded SVF

Would pair with a slowed-down playback of `nexys_a7_01.svf`. The ZCU102 `p` command plays that file with no edge delay, which the polling loop cannot follow.

### `c`: Dry Run

Parses the embedded SVF with the pin logic disabled and reports how many TCK clocks the file should produce. Use this to size a run before starting it, and to confirm the SVF blob was embedded correctly.

### `m`: Raw Monitor

Ignores the SVF entirely. Waits for TCK activity, counts every clock until the line goes idle, and prints the TMS/TDI values of the first 32 clocks. Use this when a verification run fails and you need to see whether anything sensible is arriving at all.

### `i`, `t`, `r`

`i` prints the raw channel 2 input word with TCK/TMS/TDI decoded, for wiring checks. `t` toggles the TDO output on JA1 so you can confirm the return path with an LED or a scope. `r` restores GPIO directions and drives the outputs low.

## Timing Model

Per JTAG clock, the player produces `TCK high -> TCK low -> TCK high`, then samples TDO. TMS and TDI are written in the same register write that holds TCK high, so they are already stable before the falling edge and stay stable through the rising edge.

The verifier's `pulse_tck` therefore does:

1. Wait for the TCK falling edge. The GPIO word that detected the edge also carries valid TMS and TDI, so no second read is needed.
2. Drive the expected TDO bit immediately. Real TAPs update TDO on the falling edge, so this matches JTAG convention and gives the player the whole low phase plus the rising edge as its sampling window.
3. Compare the sampled TMS/TDI against what `libxsvf` expects.
4. Wait for the TCK rising edge, which leaves the verifier aligned for the next call.

### First Clock Alignment

The player leaves TCK low between runs and parks it high inside its own `setup` callback. If the verifier simply waited for a low level it would match the idle state and mistake it for the first clock. So on clock 1 only, the verifier waits for TCK high first and then for the falling edge. This also means arming the verifier while TCK happens to already be high is harmless.

### Edge Timeouts

There is no timer peripheral in this path. Edge waits are bounded by a poll budget instead, where one poll is one AXI GPIO read:

```c
#define TCK_FIRST_EDGE_POLL_LIMIT 200000000U
#define TCK_EDGE_POLL_LIMIT 20000000U
```

An expired budget is reported as a TCK edge timeout and aborts the run, which is how a stalled player or a missed clock is surfaced rather than silently producing garbage comparisons.

SVF `RUNTEST` commands with a time component are a special case. The player really sleeps, but the verifier must not, because the two boards do not share a clock. Instead the verifier converts the requested delay into extra poll budget for the next edge wait:

```c
#define POLLS_PER_US_ESTIMATE 10U
```

This is deliberately an overestimate of the real poll rate. Overestimating only makes the verifier wait longer than necessary, whereas underestimating would cause false timeouts.

## Nothing Prints During A Capture

A blocking `xil_printf` between two TCK edges is long enough to miss the player's next clock. The reporting callbacks are therefore silent:

- `report_status` and `set_frequency` discard their arguments entirely.
- `report_error` copies the message into a fixed buffer in the context and prints it after playback.
- Mismatches are recorded into a small array and printed after playback.

Mismatch reporting is bounded on both ends:

```c
#define MISMATCH_LOG_DEPTH 16
#define MISMATCH_ABORT_LIMIT 64
```

Only the first 16 mismatching clocks are recorded in detail, and the run is aborted after 64 signal mismatches. A mismatch storm means the two `libxsvf` instances have lost lockstep, at which point every later comparison is meaningless, so continuing wastes time.

## Interpreting Failures

| Report | Likely cause |
|---|---|
| `no JTAG activity captured` | Wiring, missing common ground, `VADJ_FPGA` not at 3.3 V, or the player was started before the verifier was armed. |
| `TCK edge timeout after 0 clocks` | TCK is not reaching JA7. Check with `i` and `m`. |
| `TCK edge timeout` after many clocks | The player is clocking faster than the polling loop can follow. Use the player's `d` command, not `p`. |
| TMS mismatches from clock 1 | TMS and TDI are probably swapped, or the two boards were built from different SVF text. |
| Mismatches starting mid-run | Lost lockstep, usually a missed clock. The player's edge delay is too small. |
| Verifier passes but the player reports TDO mismatch | The TDO wire from Arty JA1 to ZCU102 J55.7 is broken, or the player's edge delay is too small for the verifier to place TDO in time. Confirm the wire with `t`. The LED demo does not check TDO. |
| `WARNING: SVF blob is not inside MIG address range` | The linker placed `.rodata` outside `0x80000000`–`0x8FFFFFFF`. The Arty script must keep the 256 MiB MIG region. |

## Keeping The Two Sides In Sync

`led_demo_svf` is duplicated in `sw/zcu102/app_svf_player/svf_player.c` and in `jtag_verifier.c`. The two copies must stay byte-identical. `libxsvf` is deterministic, so any difference in the SVF text, even whitespace, changes the generated clock sequence and desyncs the comparison.

`jtag_loop_svf` exists only in the verifier. The large embedded file is `assets/nexys_a7_01.svf` on both the Nexys and Arty verifiers. `src/UserConfig.cmake` runs `configure_file` on `svf_blob.S` so the assembler gets an absolute path at build time. Keep the file bytes and the symbol names unchanged when updating one board.

## Source Files

| File | Purpose |
|---|---|
| `jtag_verifier.c` | Main firmware, UART menu, JA GPIO setup, capture and compare `libxsvf` host callbacks |
| `svf_blob.S` | Embeds `nexys_a7_01.svf` into the ELF using `.incbin` |
| `src/UserConfig.cmake` | Vitis app source list, include paths, compile definitions, optimization |
| `src/lscript.ld` | Linker script. MIG length stays `0x10000000`. Heap default is `0x02000000`. Stack default is `0x4000`. |
| `src/Empty_applicationExample.cmake` | Same heap and stack sizes, with the Arty MIG and LMB regions left in place for a later linker regenerate |
| `platform.c`, `platform.h` | Cache enable and UART init. The 16550 path is compiled out. |

The verifier maps code, the SVF blob, a 32 MiB heap, and the stack into MIG DDR. `src/UserConfig.cmake` defines `LIBXSVF_WITHOUT_XSVF` and `LIBXSVF_WITHOUT_SCAN`. `.rodata.*` is already placed in MIG, so the `.rodata.svf` section needs no extra linker output section.

## Build Notes

Build from `sw/arty_s7/app_mb_jtag_verifier` against the exported Arty platform:

```powershell
$env:Path = 'C:\AMDDesignTools\2025.2\Vitis\gnu\microblaze\nt\bin;' + $env:Path
cmake --build build
```

The `text` size is large because the SVF file is embedded in `.rodata` (about 7.7 MiB), and the `bss` size is large because the linker reserves a 32 MiB heap. Warnings from upstream `libxsvf/svf.c` about missing field initializers are expected and harmless.

Do not replace `src/lscript.ld` with the Nexys script. That script describes 128 MiB of DDR and 128 KiB of LMB BRAM. This board has 256 MiB of DDR and 64 KiB of LMB BRAM.

## Current Limitations

- The verifier polls in software, so the player must be slowed down. This is a functional-correctness harness, not a JTAG analyzer.
- The ZCU102 player can pace only the LED demo (`d`, 100 ms). `p` has no edge delay, and there is no player command for the loop-test SVF.
- Full verification of the real bitstream SVF is about 30.6 million clocks and is not runnable against the current player.
- Verification depends on both boards parsing the same SVF. This is fine as a self-check of the signal path, but it cannot detect an SVF file that is wrong for the target device.
- The verifier presents TDO from the SVF file. It does not emulate a shift register, so it cannot detect a player that shifts the correct pattern into the wrong data register.
- TRST is accepted but not wired.
- Arming while the player is mid-run will sync to an arbitrary clock and report mismatches. Always arm first.
