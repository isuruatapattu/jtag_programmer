# MicroBlaze JTAG Verifier

This application is the counterpart to `app_mb_svf_player`. The player board turns its JA Pmod header into a software JTAG master and generates TCK/TMS/TDI. This application runs on a second Nexys A7 board, captures those signals, acts as the JTAG target, and checks that what actually arrived on the wires matches the SVF file.

Both boards use the same `pf_nexys_a7` platform in `sw/nexys_a7/ws_20260819` and bundled `external/libxsvf` sources. In this testing phase the same SVF file is embedded into both executables.

## Core Idea

The verifier does not implement a JTAG TAP state machine of its own and it does not write a second SVF parser. It runs the *same* `libxsvf_play()` over the *same* SVF bytes as the player, but its `pulse_tck` callback is inverted:

| | `app_mb_svf_player` | `app_mb_jtag_verifier` |
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

## Hardware Connections

Both boards run the same hardware design, so AXI GPIO channel 1 (JA1..JA4) is always the output channel and channel 2 (JA7..JA10) is always the input channel. The verifier therefore receives the JTAG inputs on JA7..JA9 and sends TDO back out on JA1.

| Signal | Player pin | Direction | Verifier pin |
|---|---|---|---|
| TCK | JA1 (out) | player to verifier | JA7 (in) |
| TMS | JA2 (out) | player to verifier | JA8 (in) |
| TDI | JA3 (out) | player to verifier | JA9 (in) |
| TDO | JA7 (in) | verifier to player | JA1 (out) |
| GND | GND | common | GND |

```text
Player JA1  ------->  Verifier JA7     TCK
Player JA2  ------->  Verifier JA8     TMS
Player JA3  ------->  Verifier JA9     TDI
Player JA7  <-------  Verifier JA1     TDO
Player GND  <------>  Verifier GND
```

A common ground between the two boards is required. Both headers are 3.3 V logic, so no level shifting is needed between two Nexys A7 boards.

## Clock Speed Is A Hard Constraint

The verifier detects TCK edges by polling the AXI GPIO input register from C. It needs real time between the player's falling edge and the player's TDO sample in order to place the TDO bit on the wire.

The player's original `p` command bit-bangs with `edge_delay_us = 0`, which is far too fast for a polling verifier. Two verifier-paced playback commands were added to `app_mb_svf_player` for this reason:

| Player command | SVF | Edge delay | Purpose |
|---|---|---|---|
| `l` | short loop-test SVF | 1000 us | fast end-to-end check, finishes in about a second |
| `s` | embedded `nexys_a7_01.svf` | 20 us | full-file verification, very slow |

The original `p`, `d`, `t` and `r` commands are unchanged.

Be realistic about `s`. The embedded SVF contains a single `SDR 30606304` command, so full-file verification is roughly 30.6 million JTAG clocks. At three edges per clock and 20 us per edge that is on the order of an hour. Use the verifier's `c` command to print the exact expected clock count before committing to a long run. For day-to-day checking, use the loop-test SVF.

## Test Sequence

Order matters. The verifier must be armed and polling before the player starts clocking.

1. Wire the two boards as described above, including ground.
2. Open a UART terminal to each board.
3. On the verifier, run `i` and confirm `TCK(JA7)=0`. If TCK reads 1 while the player is idle, the wiring is wrong.
4. On the verifier, press `l`. It prints `Armed. Waiting for TCK on JA7.` and starts polling.
5. On the player, press `l`.
6. The player prints its usual playback summary. The verifier prints its report.

A good run looks like this on the verifier:

```text
--- JTAG verifier report ---
libxsvf rc: 0
Captured TCK clocks: 148
TMS compares: 148, mismatches: 0
TDI compares: 66, mismatches: 0
TDO bits driven: 48
TCK edge timeouts: 0
RESULT: PASS - captured JTAG matches the SVF.
```

And on the player, `TDO mismatches` is absent, meaning the verifier's TDO drive satisfied the SVF's `TDO (...)` expectations.

Exact counts depend on how `libxsvf` sequences the TAP, so treat the numbers above as illustrative. What matters is that mismatches and timeouts are zero and the clock count agrees with the `c` dry run.

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

### `l`: Loop-Test SVF

Pairs with the player's `l`. This is the recommended end-to-end test. The loop-test SVF is short and contains `TDO (...) MASK (...)` fields, so a pass exercises all four JTAG wires including the return path.

### `d`: LED Demo SVF

Pairs with the player's existing `d` command at 100 ms per edge, which is slow enough to watch on LEDs. The demo SVF has no TDO fields, so this validates TCK/TMS/TDI capture only. Useful as a first bring-up step because the timing margin is enormous.

### `v`: Embedded SVF

Pairs with the player's `s` command. Verifies the real `nexys_a7_01.svf` bitstream file. Correct but slow; see the timing section above.

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

This is the main structural difference from `svf_player.c`, which prints status text as it goes.

Mismatch reporting is bounded on both ends:

```c
#define MISMATCH_LOG_DEPTH 16
#define MISMATCH_ABORT_LIMIT 64
```

Only the first 16 mismatching clocks are recorded in detail, and the run is aborted after 64 signal mismatches. A mismatch storm means the two `libxsvf` instances have lost lockstep, at which point every later comparison is meaningless, so continuing wastes time.

## Interpreting Failures

| Report | Likely cause |
|---|---|
| `no JTAG activity captured` | Wiring, missing common ground, or the player was started before the verifier was armed. |
| `TCK edge timeout after 0 clocks` | TCK is not reaching JA7. Check with `i` and `m`. |
| `TCK edge timeout` after many clocks | The player is clocking faster than the polling loop can follow. Use the player's `l` or `s` commands, not `p`. |
| TMS mismatches from clock 1 | TMS and TDI are probably swapped, or the two boards were built from different SVF text. |
| Mismatches starting mid-run | Lost lockstep, usually a missed clock. Lower the player's clock rate. |
| Verifier passes but the player reports TDO mismatch | The TDO wire back from verifier JA1 to player JA7 is broken, or the player's edge delay is too small for the verifier to place TDO in time. Confirm the wire with `t`. |

## Keeping The Two Sides In Sync

The built-in SVF strings are duplicated in both applications and must stay byte-identical. `libxsvf` is deterministic, so any difference in the SVF text, even whitespace, changes the generated clock sequence and desyncs the comparison. The duplicated strings are:

- `led_demo_svf`
- `jtag_loop_svf`

Both are marked with a comment in `svf_player.c` and `jtag_verifier.c`. The large embedded file is shared by pointing both `svf_blob.S` files at the same path, so it cannot drift.

## Source Files

| File | Purpose |
|---|---|
| `jtag_verifier.c` | Main firmware, UART menu, JA GPIO setup, capture and compare `libxsvf` host callbacks |
| `svf_blob.S` | Embeds `nexys_a7_01.svf` into the ELF using `.incbin` |
| `src/UserConfig.cmake` | Vitis app source list, include paths, compile definitions, optimization |
| `src/lscript.ld` | Linker script that maps code/data/SVF/heap/stack into MIG DDR |
| `platform.c`, `platform.h` | Standard platform initialization and cleanup |

The memory layout, the 32 MiB heap, the `.incbin` mechanism and the `LIBXSVF_WITHOUT_XSVF` / `LIBXSVF_WITHOUT_SCAN` definitions are all identical to `app_mb_svf_player`. See that application's README for the details, since the verifier parses the same file with the same parser and therefore has the same memory requirements.

The embedded SVF lives in `assets/nexys_a7_01.svf`. `src/UserConfig.cmake` runs `configure_file` on `svf_blob.S` so the assembler gets an absolute path at build time.

## Build Notes

Build from `sw/nexys_a7/ws_20260819/app_mb_jtag_verifier`:

```powershell
$env:Path = 'C:\AMDDesignTools\2025.2\Vitis\gnu\microblaze\nt\bin;' + $env:Path
cmake --build build
```

As with the player, the `text` size is large because the SVF file is embedded in `.rodata`, and the `bss` size is large because the linker reserves a 32 MiB heap. Warnings from upstream `libxsvf/svf.c` about missing field initializers are expected and harmless.

## Current Limitations

- The verifier polls in software, so the player must be slowed down. This is a functional-correctness harness, not a JTAG analyzer.
- Full verification of the real bitstream SVF takes on the order of an hour. The loop-test SVF is the practical regression test.
- Verification depends on both boards parsing the same SVF. This is fine as a self-check of the signal path, but it cannot detect an SVF file that is wrong for the target device.
- The verifier presents TDO from the SVF file. It does not emulate a shift register, so it cannot detect a player that shifts the correct pattern into the wrong data register.
- TRST is accepted but not wired.
- Arming while the player is mid-run will sync to an arbitrary clock and report mismatches. Always arm first.
