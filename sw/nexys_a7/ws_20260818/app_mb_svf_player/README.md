# MicroBlaze SVF Player

This application runs on the MicroBlaze system in `pf_mb_mem_gpio_uart` and turns the Nexys A7 JA Pmod header into a simple software JTAG master. It uses `libxsvf` to parse SVF commands and calls back into `svf_player.c` whenever a JTAG signal must change.

The program currently supports two useful modes:

- A real SVF player for an external JTAG target connected to JA.
- A visible LED demo mode that mimics JTAG activity when no target is connected.

The real SVF file is embedded into the executable image and placed in MIG DDR memory. The visible demo uses a short in-memory SVF string so LEDs can show the JTAG signal activity at a human-observable speed.

## Hardware Connections

The firmware uses AXI GPIO instance `XPAR_XGPIO_0_BASEADDR`, which is connected to the JA Pmod signals in the hardware design.

| JA pin | FPGA signal | AXI GPIO channel | Bit | JTAG role | Direction |
|---|---|---:|---:|---|---|
| JA1 | `ck_a0[0]` | channel 1 | bit 0 | `TCK` | output |
| JA2 | `ck_a0[1]` | channel 1 | bit 1 | `TMS` | output |
| JA3 | `ck_a0[2]` | channel 1 | bit 2 | `TDI` | output |
| JA4 | `ck_a0[3]` | channel 1 | bit 3 | unused by SVF player | output |
| JA7 | `ck_b0[0]` | channel 2 | bit 0 | `TDO` | input |
| JA8 | `ck_b0[1]` | channel 2 | bit 1 | unused | input |
| JA9 | `ck_b0[2]` | channel 2 | bit 2 | unused | input |
| JA10 | `ck_b0[3]` | channel 2 | bit 3 | unused | input |

For a real target, connect:

```text
Nexys JA1  -> target TCK
Nexys JA2  -> target TMS
Nexys JA3  -> target TDI
Nexys JA7  <- target TDO
Nexys GND  <-> target GND
```

The Nexys A7 Pmod pins are 3.3 V logic. Use level shifting if the target JTAG interface is not 3.3 V compatible.

For LED-only observation, connect LEDs through current-limiting resistors:

```text
JA1 -> resistor -> LED -> GND   shows TCK
JA2 -> resistor -> LED -> GND   shows TMS
JA3 -> resistor -> LED -> GND   shows TDI
JA4 -> resistor -> LED -> GND   optional, only used by the simple test pattern
```

Do not connect an LED directly without a resistor. A resistor from 330 ohm to 1 kOhm is suitable for a simple visual test.

## UART Commands

After boot, the firmware prints a menu over UART:

```text
Commands:
  p - play embedded SVF over JA JTAG
  d - visible LED SVF demo with no target attached
  t - run one JA output LED test pattern
  r - reset JA outputs low
Input:
```

### `p`: Real Embedded SVF Playback

Command `p` runs the large embedded SVF file:

```text
SW/app_mb_svf_player/assets/nexys_a7_01.svf
```

This is the real JTAG player path. It expects a real external target to be connected to JA. If no target is connected, this command is expected to fail with a TDO mismatch.

The failure is not a parser failure. It means the SVF file asked for a particular TDO value and the firmware sampled something else on JA7.

For example, the SVF contains an early IDCODE check:

```svf
SDR 32 TDI (00000000) TDO (03631093) MASK (0fffffff);
```

That command shifts 32 data-register bits and expects the target device to return a masked IDCODE value. With JA7 floating or disconnected, the sampled TDO bitstream will not match, so `libxsvf` reports:

```text
TDO mismatch
```

That is correct behavior for real programming mode.

### `d`: Visible LED SVF Demo

Command `d` runs a short internal SVF string named `led_demo_svf`.

It still uses `libxsvf`, so the parser and callback path are exercised, but it is intentionally short and does not require a target device. It also ignores TDO mismatch checks.

The demo SVF is:

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

The firmware slows every TCK edge using:

```c
#define LED_DEMO_EDGE_DELAY_US 100000
```

Each JTAG clock pulse is implemented as `TCK high -> TCK low -> TCK high`, with a 100 ms delay after each output state. That makes the TCK LED easy to see. This is not intended to be a real programming frequency; it is only a visual demonstration of the generated JTAG signal pattern.

Use this command when no target is connected.

### `t`: Simple JA Output Test

Command `t` does not use `libxsvf`. It simply writes a visible pattern to the four JA output bits:

```text
0x1 -> 0x2 -> 0x4 -> 0x8 -> 0xF -> 0x0
```

This is useful for confirming that LEDs and JA output pins are wired correctly before testing the SVF/JTAG path.

### `r`: Reset JA Outputs

Command `r` reconfigures JA GPIO direction and drives all JA outputs low.

Use this after tests if you want the output pins to return to a known idle-low state.

## Source Files

The important files are:

| File | Purpose |
|---|---|
| `svf_player.c` | Main firmware, UART menu, JA GPIO setup, `libxsvf` host callbacks |
| `svf_blob.S` | CMake template that embeds `assets/nexys_a7_01.svf` into the ELF using `.incbin` |
| `assets/nexys_a7_01.svf` | SVF payload embedded in the application ELF |
| `external/libxsvf/` | Local, licensed copy of the `libxsvf` parser sources and header |
| `pmod_led_test.c` | Backup of the earlier simple JA LED test; not compiled |
| `src/UserConfig.cmake` | Vitis app source list, include paths, compile definitions, optimization |
| `src/lscript.ld` | Linker script that maps code/data/SVF/heap/stack into MIG DDR |
| `platform.c`, `platform.h` | Standard platform initialization and cleanup |

The app also compiles these `libxsvf` sources:

```text
SW/app_mb_svf_player/external/libxsvf/svf.c
SW/app_mb_svf_player/external/libxsvf/tap.c
SW/app_mb_svf_player/external/libxsvf/play.c
SW/app_mb_svf_player/external/libxsvf/statename.c
SW/app_mb_svf_player/external/libxsvf/memname.c
```

`UserConfig.cmake` defines:

```cmake
LIBXSVF_WITHOUT_XSVF
LIBXSVF_WITHOUT_SCAN
```

That keeps only SVF playback enabled. XSVF and scan mode are not needed for this firmware.

## Memory Layout

The linker script maps the application into MIG DDR:

```ld
mig_7series_0_memory_0 : ORIGIN = 0x80000000, LENGTH = 0x8000000
```

This gives the MicroBlaze application 128 MiB of external DDR address space from:

```text
0x80000000 to 0x87FFFFFF
```

The SVF file is embedded by `svf_blob.S`:

```asm
.section .rodata.svf, "a"
.balign 4

.global nexys_a7_01_svf_start
.global nexys_a7_01_svf_end

nexys_a7_01_svf_start:
    .incbin "@APP_SVF_FILE@"
nexys_a7_01_svf_end:
    .balign 4
```

During CMake configuration, `UserConfig.cmake` expands `@APP_SVF_FILE@` to
the absolute location of `assets/nexys_a7_01.svf` in the current application
checkout and writes `svf_blob.generated.S` into the build directory. The
checked-in sources therefore contain no machine-specific SVF path.

The linker script includes:

```ld
.rodata : {
   __rodata_start = .;
   *(.rodata)
   *(.rodata.*)
   *(.gnu.linkonce.r.*)
   __rodata_end = .;
} > mig_7series_0_memory_0
```

Because `.rodata.svf` matches `*(.rodata.*)`, the embedded SVF file is placed in MIG DDR.

The C code refers to the embedded file using linker symbols:

```c
extern const u8 nexys_a7_01_svf_start[];
extern const u8 nexys_a7_01_svf_end[];
```

The size is computed by subtracting the two addresses:

```c
static u32 get_svf_size(void)
{
    return (u32)(nexys_a7_01_svf_end - nexys_a7_01_svf_start);
}
```

At startup and before real playback, the program prints:

```text
SVF blob address: ...
SVF blob size:    ...
```

The expected SVF size is:

```text
7,712,741 bytes
```

The heap and stack were enlarged because `libxsvf` dynamically allocates parser buffers:

```ld
_STACK_SIZE = DEFINED(_STACK_SIZE) ? _STACK_SIZE : 0x4000;
_HEAP_SIZE = DEFINED(_HEAP_SIZE) ? _HEAP_SIZE : 0x02000000;
```

The 32 MiB heap is important. The real SVF file contains a very large SDR command:

```text
SDR 30606304 TDI (...)
```

`libxsvf` reads a whole SVF command into a command buffer and parses the bit data into allocated byte arrays. With the original tiny heap, this would fail.

## Code Walkthrough

### Constants

The JA GPIO block is selected with:

```c
#define JA_GPIO_BASEADDR XPAR_XGPIO_0_BASEADDR
```

The design uses AXI GPIO channel 1 for outputs and channel 2 for inputs:

```c
#define JA_OUT_CHANNEL 1
#define JA_IN_CHANNEL 2
```

Only the low four output bits are used:

```c
#define JA_OUT_MASK 0x0000000F
```

The JTAG output bits are:

```c
#define JA_BIT_TCK 0x00000001
#define JA_BIT_TMS 0x00000002
#define JA_BIT_TDI 0x00000004
```

The TDO input bit is:

```c
#define JA_BIT_TDO 0x00000001
```

This is bit 0 of channel 2, which corresponds to JA7.

### `struct svf_player_ctx`

`struct svf_player_ctx` is the private state object passed to every `libxsvf` callback through:

```c
host->user_data = ctx;
```

It contains:

```c
XGpio *gpio;
```

The initialized AXI GPIO driver instance.

```c
const u8 *svf_data;
u32 svf_size;
u32 svf_pos;
```

The active SVF byte buffer and current read position. For real playback, this points to the embedded `.incbin` file. For LED demo playback, it points to the short `led_demo_svf` string.

```c
u32 out_shadow;
```

A software copy of the current output pin state. The code modifies bits in this shadow variable, then writes the whole value to the AXI GPIO data register.

This avoids accidentally changing unrelated bits when only one JTAG signal changes.

```c
u32 clock_count;
u32 tdi_bit_count;
u32 tdo_check_count;
```

Counters printed after playback. They help confirm that the SVF actually generated JTAG activity.

```c
u32 tdo_mismatch_count;
u32 first_mismatch_clock;
int first_mismatch_expected;
int first_mismatch_actual;
```

TDO mismatch diagnostics. On the first mismatch, the firmware records which TCK count failed and what value was expected versus sampled.

```c
u32 edge_delay_us;
int ignore_tdo;
```

These are used by the LED demo mode. `edge_delay_us` slows the TCK pulse edges. `ignore_tdo` allows the demo to run without an attached target.

### `init_ja_gpio`

```c
static int init_ja_gpio(XGpio *Gpio)
```

This initializes the AXI GPIO driver:

1. Look up the GPIO configuration for `XPAR_XGPIO_0_BASEADDR`.
2. Fail if the config is not found.
3. Call `XGpio_CfgInitialize`.

This does not configure pin directions. It only prepares the Xilinx GPIO driver instance.

### `configure_ja_gpio`

```c
static void configure_ja_gpio(XGpio *Gpio)
```

This sets the JA GPIO directions:

```c
XGpio_SetDataDirection(Gpio, JA_OUT_CHANNEL, 0x00000000);
```

For AXI GPIO, direction bit `0` means output. This makes channel 1 output.

```c
XGpio_SetDataDirection(Gpio, JA_IN_CHANNEL, 0xFFFFFFFF);
```

Direction bit `1` means input. This makes channel 2 input.

```c
XGpio_DiscreteWrite(Gpio, JA_OUT_CHANNEL, 0x00000000);
```

All JA output bits start low.

### `test_ja_outputs`

```c
static void test_ja_outputs(XGpio *Gpio)
```

This is the simple non-SVF LED test used by UART command `t`.

It writes:

```text
0x1
0x2
0x4
0x8
0xF
0x0
```

to JA channel 1 with a 300 ms delay between values.

This verifies the physical LED wiring and output GPIO path. It does not test SVF parsing.

### `svf_write_outputs`

```c
static void svf_write_outputs(struct svf_player_ctx *ctx)
```

This writes the shadow output word directly to the AXI GPIO channel 1 data register:

```c
XGpio_WriteReg(ctx->gpio->BaseAddress, XGPIO_DATA_OFFSET,
               ctx->out_shadow & JA_OUT_MASK);
```

The code uses the low-level register macro instead of `XGpio_DiscreteWrite` in the JTAG pulse path because the pulse path is called once per JTAG clock and should be as direct as possible.

`XGPIO_DATA_OFFSET` is channel 1 data register offset `0x0`.

### `svf_read_tdo`

```c
static int svf_read_tdo(struct svf_player_ctx *ctx)
```

This reads AXI GPIO channel 2:

```c
input_value = XGpio_ReadReg(ctx->gpio->BaseAddress, XGPIO_DATA2_OFFSET);
```

`XGPIO_DATA2_OFFSET` is channel 2 data register offset `0x8`.

Then it extracts bit 0:

```c
return ((input_value & JA_BIT_TDO) != 0U) ? 1 : 0;
```

That bit is JA7, the TDO input.

## How `libxsvf` Is Used

`libxsvf` does not know anything about MicroBlaze, AXI GPIO, UART, or JA pins. It only knows how to parse SVF and ask a host application to perform low-level operations.

The firmware provides those operations using `struct libxsvf_host`.

The setup happens in:

```c
static void init_svf_host(struct libxsvf_host *host, struct svf_player_ctx *ctx)
```

This function clears the host struct and assigns callbacks:

```c
host->setup = mb_svf_setup;
host->shutdown = mb_svf_shutdown;
host->udelay = mb_svf_udelay;
host->getbyte = mb_svf_getbyte;
host->sync = mb_svf_sync;
host->pulse_tck = mb_svf_pulse_tck;
host->pulse_sck = mb_svf_pulse_sck;
host->set_trst = mb_svf_set_trst;
host->set_frequency = mb_svf_set_frequency;
host->report_device = mb_svf_report_device;
host->report_status = mb_svf_report_status;
host->report_error = mb_svf_report_error;
host->realloc = mb_svf_realloc;
host->user_data = ctx;
```

Then playback is started with:

```c
rc = libxsvf_play(&host, LIBXSVF_MODE_SVF);
```

From that point, `libxsvf` drives the process:

1. It calls `setup`.
2. It repeatedly calls `getbyte` to read SVF text.
3. It parses commands like `STATE`, `SIR`, `SDR`, and `RUNTEST`.
4. It calls `pulse_tck` for each JTAG clock.
5. It calls `udelay` for SVF delays and TCK-count runtests.
6. It calls `realloc` when parser buffers need memory.
7. It calls `report_error` if syntax, allocation, or TDO checks fail.
8. It calls `shutdown` at the end.

## Callback Details

### `mb_svf_setup`

This is called by `libxsvf_play` before parsing starts.

It resets runtime counters:

```c
ctx->svf_pos = 0;
ctx->clock_count = 0;
ctx->tdi_bit_count = 0;
ctx->tdo_check_count = 0;
```

It sets TCK high:

```c
ctx->out_shadow = JA_BIT_TCK;
```

The pulse function uses a negative TCK pulse:

```text
TCK high -> TCK low -> TCK high
```

This matches the style expected by this `libxsvf` port.

Then it configures the GPIO and writes the initial output state.

### `mb_svf_shutdown`

This is called when playback ends or fails.

It drives all JA outputs low:

```c
ctx->out_shadow = 0;
svf_write_outputs(ctx);
```

### `mb_svf_getbyte`

This callback supplies SVF text bytes to the parser.

```c
if (ctx->svf_pos >= ctx->svf_size) {
    return -1;
}

return (int)ctx->svf_data[ctx->svf_pos++];
```

The same function works for both SVF sources:

- The embedded real SVF file.
- The short LED demo SVF string.

Returning `-1` means end of file.

### `mb_svf_pulse_tck`

This is the most important callback. Every JTAG bit passes through this function.

Its parameters are provided by `libxsvf`:

| Parameter | Meaning |
|---|---|
| `tms` | Value to drive on TMS |
| `tdi` | Value to drive on TDI, or `-1` if TDI should be left unchanged |
| `tdo` | Expected TDO value, or `-1` if no TDO check is needed |
| `rmask` | Non-standard return-mask bit; this firmware only uses it to decide whether TDO should be sampled |
| `sync` | Used by async interfaces; ignored here because GPIO access is synchronous |

The function first updates TMS:

```c
if (tms != 0) {
    ctx->out_shadow |= JA_BIT_TMS;
} else {
    ctx->out_shadow &= ~JA_BIT_TMS;
}
```

Then it updates TDI if requested:

```c
if (tdi >= 0) {
    ctx->tdi_bit_count++;
    if (tdi != 0) {
        ctx->out_shadow |= JA_BIT_TDI;
    } else {
        ctx->out_shadow &= ~JA_BIT_TDI;
    }
}
```

Then it creates one TCK pulse:

```c
ctx->out_shadow |= JA_BIT_TCK;
svf_write_outputs(ctx);

ctx->out_shadow &= ~JA_BIT_TCK;
svf_write_outputs(ctx);

ctx->out_shadow |= JA_BIT_TCK;
svf_write_outputs(ctx);
```

In demo mode, each output state is followed by:

```c
usleep(ctx->edge_delay_us);
```

That is what makes the LEDs visible.

After the clock, the function samples TDO if the parser requested it:

```c
should_read_tdo = (tdo >= 0) || (rmask != 0);
```

If an expected TDO value exists and `ignore_tdo` is false, the sampled TDO is compared against the expected value:

```c
if ((ctx->ignore_tdo == 0) && (line_tdo != tdo)) {
    ...
    return -1;
}
```

Returning `-1` tells `libxsvf` there was a TDO mismatch.

This is why command `p` fails when no target is connected.

Command `d` sets `ignore_tdo = 1`, so it can run without a target.

### `mb_svf_udelay`

SVF `RUNTEST` commands can request a time delay, a number of TCK clocks, or both.

This callback handles both:

```c
while (num_tck > 0) {
    (void)mb_svf_pulse_tck(h, tms, -1, -1, 0, 0);
    num_tck--;
}

delay_us_long(usecs);
```

For TCK-count delays, it repeatedly calls the same TCK pulse function. That means `RUNTEST 8 TCK` visibly toggles JA1 in demo mode.

For time delays, it calls `delay_us_long`.

`delay_us_long` breaks large delays into 1-second chunks before calling `usleep`. This avoids depending on `usleep` accepting very large values.

### `mb_svf_set_frequency`

SVF files may contain a `FREQUENCY` command:

```svf
FREQUENCY 1.00E+07 HZ;
```

The callback accepts the command and prints the requested frequency:

```c
xil_printf("SVF requested JTAG frequency: %d Hz; using GPIO bit-bang speed.\r\n",
           frequency_hz);
return 0;
```

The firmware does not enforce the requested frequency. AXI GPIO bit-banging from C is much slower than 10 MHz. For JTAG programming this is usually acceptable, but it will take longer.

The visible LED demo uses `FREQUENCY 3 HZ`, but that is mainly descriptive. The actual visible delay is controlled by `LED_DEMO_EDGE_DELAY_US`.

### `mb_svf_set_trst`

The real SVF file contains:

```svf
TRST OFF;
```

There is no TRST pin assigned on JA, so this callback intentionally does nothing:

```c
(void)value;
```

It still exists so `libxsvf` can accept `TRST` commands.

### `mb_svf_realloc`

`libxsvf` asks the host application for memory through a callback:

```c
static void *mb_svf_realloc(struct libxsvf_host *h, void *ptr, int size,
                            enum libxsvf_mem which)
```

This firmware uses the C library heap:

```c
return realloc(ptr, (size_t)size);
```

For `size <= 0`, it frees the pointer:

```c
free(ptr);
return NULL;
```

This is why the linker heap size matters.

### Reporting Callbacks

`mb_svf_report_status` prints SVF command text, but through `print_limited`.

That matters because the real SVF contains a huge SDR command. Printing the whole command over UART would be extremely slow and not useful.

The limit is:

```c
#define STATUS_PRINT_LIMIT 96
```

`mb_svf_report_error` also truncates long messages for the same reason.

## Playback Flow

### Real SVF Flow

Command `p` calls:

```c
play_embedded_svf(&JaGpio);
```

That function prints the embedded SVF location and calls:

```c
play_svf_buffer(Gpio, nexys_a7_01_svf_start, get_svf_size(), 0, 0);
```

The final two arguments mean:

```text
edge_delay_us = 0
ignore_tdo    = 0
```

So real playback runs as fast as the software GPIO path allows and enforces TDO checks.

### LED Demo Flow

Command `d` calls:

```c
play_led_demo_svf(&JaGpio);
```

That function calls:

```c
play_svf_buffer(Gpio, led_demo_svf,
                (u32)(sizeof(led_demo_svf) - 1U),
                LED_DEMO_EDGE_DELAY_US,
                1);
```

The final two arguments mean:

```text
edge_delay_us = 100000
ignore_tdo    = 1
```

So demo playback is slow enough for LEDs and does not fail when no target drives TDO.

### Shared Playback Function

Both modes use:

```c
static int play_svf_buffer(XGpio *Gpio, const u8 *svf_data, u32 svf_size,
                           u32 edge_delay_us, int ignore_tdo)
```

This function:

1. Clears a `struct svf_player_ctx`.
2. Stores the GPIO pointer.
3. Stores the SVF buffer pointer and size.
4. Stores demo/real playback options.
5. Initializes the `libxsvf_host`.
6. Calls `libxsvf_play`.
7. Prints the result and counters.

This shared function is why the real file and demo string use the same parser and JTAG callback path.

## Why TDO Mismatch Happens Without A Target

JTAG has four main signals:

```text
TCK: clock driven by programmer
TMS: mode/state control driven by programmer
TDI: data into target driven by programmer
TDO: data out of target driven by target
```

The MicroBlaze firmware drives TCK/TMS/TDI. It cannot invent correct TDO data for a real target. TDO must come from the device being programmed.

When the SVF says:

```svf
TDO (03631093) MASK (0fffffff)
```

it means:

1. Shift bits through the JTAG data register.
2. Read TDO from the target.
3. Compare the read value against `03631093`.
4. Only compare the bits selected by `MASK`.

With no target connected, JA7 is not driven by a real device. It might read as 0, 1, or a noisy/floating value. That cannot match the expected IDCODE reliably.

Therefore:

```text
[SVF ERROR] ... TDO mismatch
```

is expected and correct.

Use `d` for no-target LED observation. Use `p` only when a real target is connected.

## Build Notes

Build from:

```text
SW/app_mb_svf_player
```

Using CMake:

```powershell
$env:Path = 'C:\AMDDesignTools\2025.2\Vitis\gnu\microblaze\nt\bin;' + $env:Path
cmake --build build
```

The MicroBlaze bin path is needed because the generated build runs `mb-size` after linking.

Successful build output ends with something like:

```text
Linking C executable app_mb_svf_player.elf
   text    data      bss      dec      hex filename
7747420    1624 33571276 41320320 2767f80 app_mb_svf_player.elf
```

The large `text` size is expected because the SVF file is embedded in `.rodata`.

The large `bss` size is expected because the linker reserves a 32 MiB heap.

You may see warnings from upstream `libxsvf/svf.c` like:

```text
warning: missing initializer for field 'has_tdo_data'
```

Those warnings are not from `svf_player.c`. The missing field is automatically initialized to zero by C, so the build still links successfully.

## Expected Runtime Behavior

### With LEDs Only

Use command `t` first. LEDs should show:

```text
JA1 on
JA2 on
JA3 on
JA4 on
all on
all off
```

Then use command `d`. LEDs on JA1, JA2, and JA3 should show JTAG-like activity:

- JA1 toggles as TCK.
- JA2 changes as TMS moves the TAP state machine.
- JA3 changes as TDI data is shifted.

No target is needed for `d`.

### With No Target And Command `p`

The real embedded SVF starts, then fails at a TDO check. This is expected.

Typical symptom:

```text
[SVF ERROR] ... TDO mismatch
SVF playback finished with rc=-1
```

### With A Real Target

Connect JA1/JA2/JA3/JA7/GND to the target JTAG header. Then command `p` should run the full embedded SVF.

If the target is wrong, absent, held in reset, powered incorrectly, voltage-incompatible, or wired incorrectly, the most likely failure is still TDO mismatch.

## Practical Debug Checklist

1. Run `t`.
2. Confirm JA1-JA4 LEDs work.
3. Run `d`.
4. Confirm JA1/JA2/JA3 show slower JTAG-like activity.
5. Connect real target JTAG and shared ground.
6. Run `p`.
7. If `p` fails with TDO mismatch, check JA7, target power, target voltage, target chain, and whether the SVF matches the target device.

## Current Limitations

- JTAG is bit-banged through AXI GPIO, so it is much slower than the SVF-requested 10 MHz.
- TRST is accepted but not physically driven.
- TDO is only read from JA7.
- The firmware does not auto-detect JTAG chains.
- The embedded SVF is fixed at build time. To change it, replace the file referenced by `svf_blob.S` and rebuild.
- The real SVF command `p` is intended for an external target, not for reprogramming the same FPGA fabric that is running the MicroBlaze design.
