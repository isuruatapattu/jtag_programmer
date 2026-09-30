# 04 JTAG Implementation

`libxsvf` parses SVF text. It does not know about MicroBlaze, Cortex-A53, AXI, or Pmod pins. The application supplies a `struct libxsvf_host`: a byte source for the SVF, a function that pulses TCK, and a heap allocator. Both `app_mb_svf_player/svf_player.c` and `app_svf_player/svf_player.c` implement that host the same way.

The line-by-line commentary for the Nexys A7 file is in the [application README](../sw/nexys_a7/ws_20260818/app_mb_svf_player/README.md). Player sources are in `sw/nexys_a7/app_mb_svf_player`. This page is the hardware-facing contract.

## Pin bits

The GPIO base is `XPAR_XGPIO_0_BASEADDR`. Channel 1 is the output data register at offset `0x0`. Channel 2 is the input data register at offset `0x8`.

| Bit | Mask | Signal |
|---|---|---|
| channel 1, bit 0 | `0x1` | TCK |
| channel 1, bit 1 | `0x2` | TMS |
| channel 1, bit 2 | `0x4` | TDI |
| channel 2, bit 0 | `0x1` | TDO |

`out_shadow` holds the last output word. Each callback updates TMS or TDI in that shadow, then writes the whole nibble. Unrelated bits stay put.

## One TCK cycle

`mb_svf_pulse_tck` is called once per JTAG clock. `libxsvf` passes TMS, an optional TDI bit (`-1` means leave TDI alone), an optional expected TDO bit (`-1` means do not check), and a return mask.

The pulse is negative, which is the edge order this port of `libxsvf` is written for:

```text
TCK high  ->  write GPIO
TCK low   ->  write GPIO
TCK high  ->  write GPIO
sample TDO if a check was requested
```

Setup starts with TCK already high, so the first edge the target sees is the falling edge. Shutdown drives all four output bits low.

In demo mode each of those three writes is followed by `usleep(100000)`. Real playback (`p`) uses a delay of 0 and runs at the speed of the GPIO writes.

TDO is sampled after the pulse when the parser asked for a value or set the return mask. If `ignore_tdo` is clear and the sampled bit differs from the expected bit, the callback records the clock count and both bit values, then returns `-1`. `libxsvf` stops and reports a TDO mismatch. Demo mode sets `ignore_tdo`, so a floating JA7 or J55.7 does not fail the run.

## Host callbacks

`libxsvf_play(&host, LIBXSVF_MODE_SVF)` calls, in order:

| Callback | Behavior here |
|---|---|
| `setup` | Clear counters, park TCK high, set GPIO directions |
| `getbyte` | Next byte from the active buffer, or `-1` at the end |
| `pulse_tck` | The waveform above |
| `udelay` | Extra TCK pulses for `RUNTEST n TCK`, then a time delay split into 1 s chunks |
| `set_frequency` | Print the requested rate and return success. The GPIO path is not retimed |
| `set_trst` | Accept the command. No TRST pin is assigned |
| `realloc` | C `realloc` / `free` on the application heap |
| `report_status`, `report_error` | UART text, truncated to 96 characters |
| `report_device` | Print the IDCODE `libxsvf` shifted in |
| `shutdown` | Outputs low |

`FREQUENCY 1.00E+07 HZ` in the real SVF is therefore a record of what Vivado asked for, not the clock the pins produce. AXI GPIO writes from C are far slower than 10 MHz. JTAG configuration still completes; it takes longer than a USB-JTAG pod.

`TRST OFF` is in the SVF and is ignored electrically. The 7-series TAP is reset by five or more TCK pulses with TMS held high, which `STATE RESET` already generates.

## What is compiled

`src/UserConfig.cmake` builds the player plus these `libxsvf` files:

```text
svf.c  tap.c  play.c  statename.c  memname.c
```

`LIBXSVF_WITHOUT_XSVF` and `LIBXSVF_WITHOUT_SCAN` leave XSVF and scan mode out. Optimization is `-O2`.

## Where the SVF lives

`svf_blob.S` is a template:

```asm
.section .rodata.svf, "a"
.incbin "@APP_SVF_FILE@"
```

CMake writes `svf_blob.generated.S` into the build directory with `@APP_SVF_FILE@` replaced by the absolute path of `assets/nexys_a7_01.svf`. The checked-in sources do not contain a machine-specific path.

The Nexys A7 linker script maps `.text` and `.rodata` (including `.rodata.svf`) to:

```text
mig_7series_0_memory_0 : ORIGIN = 0x80000000, LENGTH = 0x8000000
```

The ZCU102 script maps the same sections to `psu_ddr_0` (`ORIGIN = 0x0`, almost 2 GiB). On both targets the heap is 32 MiB and the stack is 16 KiB:

```text
_HEAP_SIZE = 0x02000000
_STACK_SIZE = 0x4000
```

The 32 MiB heap is required. `libxsvf` reads a whole command before executing it, and the configuration command is an `SDR` of 30,606,304 bits. A default heap cannot hold that command buffer and the parsed bit arrays.

The C code sees the blob through linker symbols `nexys_a7_01_svf_start` and `nexys_a7_01_svf_end`. The size printed at startup is the difference of those addresses. The application notes record 7,712,741 bytes for this file.
