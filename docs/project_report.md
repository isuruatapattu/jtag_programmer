# FPGA JTAG Programmer

**Project report**

October 2026

## Abstract

This project turns a general-purpose FPGA board into a JTAG master. Embedded software parses a Serial Vector Format (SVF) file with `libxsvf` and bit-bangs the target Test Access Port through an AXI GPIO block. There is no JTAG cable IP and no vendor programming pod in the data path.

Two programmer platforms share the same player design. A Digilent Nexys A7 runs the player on MicroBlaze and drives Pmod JA. A Xilinx ZCU102 runs the same player on a Cortex-A53 and drives Pmod J55. The checked-in SVF configures a second Nexys A7-100T (Artix-7 XC7A100T). A companion verifier on a Nexys A7 captures the ZCU102 waveforms and checks them against the same SVF.

A completed configuration reports `rc=0`, a non-zero TDO check count, and a lit DONE LED on the target. Playback is slower than a USB-JTAG pod because each JTAG clock is several AXI GPIO writes from C.

## 1. Introduction

Configuring an FPGA over JTAG normally requires a vendor cable and host software. This project replaces that path with a board that is already on the bench. The programmer FPGA runs a small standalone application. The application reads an SVF file that was recorded from a bitstream, and it drives TCK, TMS, and TDI while sampling TDO.

The programmer board and the target board are different boards. The SVF configures the target. It does not reconfigure the FPGA that is executing the player. Programming the same device that is running the player would replace the player and stop the transfer.

The current asset, `assets/nexys_a7_01.svf`, is a Vivado configuration SVF for one device:

- The instruction length is 6 bits, which matches a 7-series TAP.
- Chain padding is zero (`HIR 0`, `TIR 0`, `HDR 0`, `TDR 0`), so the Artix-7 must be the only device on the scan chain.
- The IDCODE check expects `0x03631093` with mask `0x0FFFFFFF`. That is the XC7A100T on a Nexys A7-100T. The mask ignores the 4-bit revision field.
- The configuration payload is one data shift of 30,606,304 bits, followed by the startup and status checks Vivado emits.

## 2. Objectives

1. Drive a standard 4-wire JTAG port from an FPGA GPIO block under software control.
2. Play a vendor-generated SVF, including a full Artix-7 configuration, without a programming cable in the data path.
3. Support the same player on a soft-core MicroBlaze system and on a Zynq UltraScale+ Cortex-A53.
4. Provide bring-up commands that exercise the pins before a target is attached.
5. Provide a second board that can capture the programmer's waveforms and compare them with the SVF.

## 3. Background

### 3.1 JTAG

IEEE 1149.1 defines a Test Access Port of four required signals:

| Signal | Direction from the master | Role |
|---|---|---|
| TCK | Output | Clock |
| TMS | Output | TAP state |
| TDI | Output | Data into the target |
| TDO | Input | Data out of the target |

An optional TRST pin is not used. The 7-series TAP is reset by five or more TCK pulses with TMS held high. The SVF `STATE RESET` sequence already generates that pattern. `TRST OFF` is accepted by the player and does not move a wire.

The target TAP on a Nexys A7 is header J10. The same TAP is also reached by the onboard USB-JTAG circuit on J6. Two masters on TCK, TMS, and TDI will contend, so the target's PROG USB cable stays unplugged for the whole SVF run.

### 3.2 SVF

Serial Vector Format is a text record of JTAG operations: state moves, instruction shifts (`SIR`), data shifts (`SDR`), run-test delays, and expected TDO values with masks. `libxsvf` parses that text. It does not know about MicroBlaze, Cortex-A53, AXI, or Pmod pins. The application supplies a host: a byte source for the SVF, a function that pulses TCK, and a heap allocator.

The player does not read a bitstream. It plays an SVF that already contains the JTAG operations for one configuration. Changing the bitstream means generating a new SVF, replacing the asset, and rebuilding the ELF. There is no runtime download of the file.

## 4. System architecture

```text
Host PC                         Programmer board                    Target board
Vivado  -- bitstream / SVF -->  CPU + DDR + AXI GPIO  -- TCK  -->   Nexys A7 J10
Vitis   -- ELF with SVF ----->  UART console          -- TMS  -->   XC7A100T TAP
                                Pmod pins             -- TDI  -->
                                                      <-- TDO --
                                                      --- GND ---
```

Vivado records a program operation into an SVF. The SVF is linked into the player ELF. At run time the CPU parses the file and writes a GPIO data register. The Pmod pins are the only connection to the target TAP.

| | Nexys A7 programmer | ZCU102 programmer |
|---|---|---|
| Project | `hw/nexys_a7_jtag_programmer` and `hw/nexys_a7_jtag_programmer_2025.01` | `hw/zcu102_jtag_programmer` |
| CPU | MicroBlaze | Cortex-A53, standalone domain |
| Application | `sw/nexys_a7/app_mb_svf_player` | `sw/zcu102/app_svf_player` |
| JTAG connector | Pmod JA | Pmod J55 |
| Program memory | 128 MiB DDR2 at `0x80000000` | PS DDR (`psu_ddr_0`) |
| Console | Board USB-UART (AXI UART Lite), preset 9600 8N1 | PS UART, 115200 8N1 |

The player source is the same design on both platforms: dual-channel AXI GPIO, channel 1 outputs, channel 2 inputs, and the same bit assignment (bit 0 TCK, bit 1 TMS, bit 2 TDI, input bit 0 TDO). The ZCU102 binary still prints the Nexys pin names (`JA1`, `JA2`, `JA3`, `JA7`). On that board those names mean the J55 pins.

A third application, `sw/nexys_a7/app_mb_jtag_verifier`, runs on a Nexys A7 and acts as the JTAG target for the ZCU102 player. It walks the same SVF with `libxsvf` and compares the wires against the parser's expected bits.

## 5. Hardware design

### 5.1 Nexys A7 programmer

The Nexys A7 programmer is a MicroBlaze system with DDR2, a UART, a board GPIO for LEDs and switches, and a second GPIO used only as the JTAG port.

The block design uses these IP cores: MicroBlaze 11.0, MIG 7-series 4.2, Clocking Wizard 6.0, two AXI GPIO 2.0 cores, AXI UART Lite 2.0, SmartConnect 1.0, MDM 3.2, and local-memory LMB with a 128 KiB BRAM. MicroBlaze is built with the debug module, a data-side AXI interface, and 32 KiB instruction and data caches.

The board clock is `clk_100MHz`. The clock wizard produces the system clock for MicroBlaze, the LMB, both GPIO cores, the UART, and one SmartConnect. A second wizard output, requested at 200 MHz, is the MIG reference clock. The MIG user clock has its own reset, and a second SmartConnect sits on that domain so the instruction and data caches can reach DDR.

MicroBlaze data space:

| Peripheral | Base | Range |
|---|---|---|
| LMB BRAM | `0x00000000` | 128 KiB |
| `axi_gpio_0` (JTAG) | `0x40000000` | 64 KiB |
| `axi_gpio_1` (LEDs, switches) | `0x40010000` | 64 KiB |
| `axi_uartlite_0` | `0x40600000` | 64 KiB |
| MIG DDR2 | `0x80000000` | 128 MiB |

Instruction space maps the same LMB and the same DDR window. The linker script places the application, including the embedded SVF, in the DDR window. Vectors stay in the local BRAM.

`axi_gpio_0` is the programmer port. Both channels are 4 bits wide. Channel 1 is all outputs and drives board port `ck_a0`. Channel 2 is wired from input port `ck_b0`. The firmware also programs the direction registers: channel 1 all outputs, channel 2 all inputs. `axi_gpio_1` is the board LED and switch interface and is not used by the SVF player.

Pmod JA pinout:

| JA pin | FPGA pin | GPIO | JTAG | Direction |
|---|---|---|---|---|
| JA1 | C17 | channel 1, bit 0 | TCK | output |
| JA2 | D18 | channel 1, bit 1 | TMS | output |
| JA3 | E18 | channel 1, bit 2 | TDI | output |
| JA4 | G17 | channel 1, bit 3 | unused | output |
| JA7 | D17 | channel 2, bit 0 | TDO | input |
| JA8 | E17 | channel 2, bit 1 | unused | input |
| JA9 | F18 | channel 2, bit 2 | unused | input |
| JA10 | G18 | channel 2, bit 3 | unused | input |

Pins 5 and 11 are ground. Pins 6 and 12 are 3.3 V and are not connected to the target.

### 5.2 ZCU102 programmer

The ZCU102 constraints place the same 4-bit output and 4-bit input buses on Pmod J55, all LVCMOS33. The processing system supplies the Cortex-A53 clock, DDR, and the 115200 baud console. The player looks up `XPAR_XGPIO_0_BASEADDR` and uses channel 1 as the output register and channel 2 as the input register.

| J55 pin | FPGA pin | JTAG | Direction |
|---|---|---|---|
| J55.1 | A20 | TCK | output |
| J55.3 | B20 | TMS | output |
| J55.5 | A22 | TDI | output |
| J55.2 | B21 | unused | output |
| J55.7 | A21 | TDO | input |
| J55.4 | C21 | unused | input |
| J55.6 | C22 | unused | input |
| J55.8 | D21 | unused | input |

J55 is on bank 47, powered by `VADJ_FPGA`. The constraints use LVCMOS33, so `VADJ_FPGA` is set to 3.3 V before the header is connected to a Nexys A7.

### 5.3 Target

The target is a second Nexys A7. Header J10 is a single-device TAP, which matches an SVF generated with no header or trailer bits.

```text
Programmer TCK  ->  target J10 TCK
Programmer TMS  ->  target J10 TMS
Programmer TDI  ->  target J10 TDI
Programmer TDO  <-  target J10 TDO
Programmer GND <->  target J10 GND
```

The J10 VREF pin is left open. The programmer does not source or load that pin. JP3 selects the barrel jack, the PROG USB plug is out, and JP1 is in the JTAG position so QSPI, microSD, or USB cannot load a different bitstream after the SVF finishes. The target is powered and out of reset before playback starts. The DONE LED lights after a successful configuration.

Pmod JA on the Nexys A7 and J55 in this ZCU102 design are LVCMOS33. The Nexys A7 JTAG bank is 3.3 V, so a Nexys-to-Nexys or ZCU102-to-Nexys connection does not need level shifters. Any other target voltage does. The grounds are always connected. The programmer's 3.3 V pin is never tied to the target.

### 5.4 Repository layout

```text
hw/nexys_a7_jtag_programmer/             Vivado project
hw/nexys_a7_jtag_programmer_2025.01/     Recreate Tcl for the 2025.1 flow
hw/zcu102_jtag_programmer/               ZCU102 project and J55 constraints
sw/nexys_a7/app_mb_svf_player/           MicroBlaze SVF player
sw/nexys_a7/app_mb_jtag_verifier/        MicroBlaze JTAG verifier
sw/nexys_a7/ws_20260819/                 Vitis workspace and pf_nexys_a7 platform
sw/zcu102/app_svf_player/                Cortex-A53 SVF player
sw/zcu102/app_hello_world/               Cortex-A53 hello world
sw/zcu102/ws_20260819/                   Vitis workspace and pf_zynq platform
docs/                                    Documentation
```

Vivado project files (`.xpr`), exported hardware (`.xsa`), and bitstreams (`.bit`) are kept in version control. Generated implementation directories, Vitis build trees, and ELF files are ignored.

## 6. Firmware

### 6.1 Host callbacks

`libxsvf_play` is called in SVF mode. The application implements `struct libxsvf_host`:

| Callback | Behavior |
|---|---|
| `setup` | Clear counters, park TCK high, set GPIO directions |
| `getbyte` | Next byte from the active buffer, or `-1` at the end |
| `pulse_tck` | One JTAG clock, described below |
| `udelay` | Extra TCK pulses for `RUNTEST n TCK`, then a time delay split into 1 s chunks |
| `set_frequency` | Print the requested rate and return success. The GPIO path is not retimed |
| `set_trst` | Accept the command. No TRST pin is assigned |
| `realloc` | C `realloc` / `free` on the application heap |
| `report_status`, `report_error` | UART text, truncated to 96 characters |
| `report_device` | Print the IDCODE `libxsvf` shifted in |
| `shutdown` | Outputs low |

The build compiles `svf.c`, `tap.c`, `play.c`, `statename.c`, and `memname.c` from `libxsvf`. `LIBXSVF_WITHOUT_XSVF` and `LIBXSVF_WITHOUT_SCAN` leave XSVF and scan mode out. Optimization is `-O2`.

### 6.2 TCK waveform

The GPIO base is `XPAR_XGPIO_0_BASEADDR`. Channel 1 is the output data register at offset `0x0`. Channel 2 is the input data register at offset `0x8`.

| Bit | Mask | Signal |
|---|---|---|
| channel 1, bit 0 | `0x1` | TCK |
| channel 1, bit 1 | `0x2` | TMS |
| channel 1, bit 2 | `0x4` | TDI |
| channel 2, bit 0 | `0x1` | TDO |

`out_shadow` holds the last output word. Each callback updates TMS or TDI in that shadow, then writes the whole nibble. Unrelated bits stay put.

`mb_svf_pulse_tck` is called once per JTAG clock. `libxsvf` passes TMS, an optional TDI bit (`-1` means leave TDI alone), an optional expected TDO bit (`-1` means do not check), and a return mask. The pulse is negative, which is the edge order this port of `libxsvf` is written for:

```text
TCK high  ->  write GPIO
TCK low   ->  write GPIO
TCK high  ->  write GPIO
sample TDO if a check was requested
```

Setup starts with TCK already high, so the first edge the target sees is the falling edge. Shutdown drives all four output bits low.

In demo mode each of those three writes is followed by `usleep(100000)`. Real playback uses a delay of 0 and runs at the speed of the GPIO writes.

TDO is sampled after the pulse when the parser asked for a value or set the return mask. If `ignore_tdo` is clear and the sampled bit differs from the expected bit, the callback records the clock count and both bit values, then returns `-1`. `libxsvf` stops and reports a TDO mismatch. Demo mode sets `ignore_tdo`, so a floating TDO pin does not fail the run.

`FREQUENCY 1.00E+07 HZ` in the real SVF is a record of what Vivado asked for. AXI GPIO writes from C are far slower than 10 MHz. JTAG configuration still completes; it takes longer than a USB-JTAG pod.

### 6.3 Where the SVF lives

`svf_blob.S` is a template:

```asm
.section .rodata.svf, "a"
.incbin "@APP_SVF_FILE@"
```

CMake writes `svf_blob.generated.S` into the build directory with `@APP_SVF_FILE@` replaced by the absolute path of `assets/nexys_a7_01.svf`. The checked-in sources do not contain a machine-specific path. The C code sees the blob through linker symbols `nexys_a7_01_svf_start` and `nexys_a7_01_svf_end`. The size printed at startup is the difference of those addresses.

On the Nexys A7 the linker maps `.text` and `.rodata` (including `.rodata.svf`) to DDR at `0x80000000`, length 128 MiB. On the ZCU102 the same sections map to `psu_ddr_0` at `0x0`. On both targets the heap is 32 MiB and the stack is 16 KiB.

The 32 MiB heap is required. `libxsvf` reads a whole command before executing it, and the configuration command is an `SDR` of 30,606,304 bits. A default heap cannot hold that command buffer and the parsed bit arrays. If a rebuilt SVF is substantially larger, `_HEAP_SIZE` in `src/lscript.ld` is raised, and the heap stays inside the DDR region.

### 6.4 UART commands

The UART menu is the whole user interface. The loop never exits.

| Key | Mode | Target required |
|---|---|---|
| `t` | Walk a 4-bit pattern on the output pins (`1, 2, 4, 8, F, 0`, 300 ms per step) | No |
| `d` | Short SVF, slowed to about 100 ms per edge, TDO ignored | No |
| `p` | Embedded configuration SVF at GPIO speed, TDO checked | Yes |
| `r` | Drive the outputs low | No |

`t` does not call `libxsvf`. It is the first check that the output wiring and the bitstream are the JTAG design. `d` plays a short string compiled into the ELF: reset, idle, an IDCODE instruction, a 32-bit data shift, eight run-test clocks, and a short `0x55AA` shift. `p` is the programming path. Every TDO expectation in the file is enforced. The first one is the IDCODE shift, so a missing or wrong target fails immediately and the large configuration shift never starts.

Phases inside the configuration file:

| SVF section | JTAG effect |
|---|---|
| `STATE RESET` / `STATE IDLE` | TMS sequences the TAP through Test-Logic-Reset into Run-Test/Idle |
| `SIR 6 TDI (09)` + 32-bit `SDR` | Shift the IDCODE instruction and read 32 bits. Expect `0x03631093` under mask `0x0FFFFFFF` |
| `SIR 6 TDI (0b)` | JPROGRAM |
| `SIR 6 TDI (14)` and the `RUNTEST` pair | Initialization poll, including a 0.1 s wait and 10,000 clocks |
| `SIR 6 TDI (05)` + `SDR 30606304` | Shift the configuration bitstream into the device |
| `config/start` | `JSTART` (`0x0C`) and clocks that complete startup |
| `config/status` | Status read. One bit is checked under mask `0x08000000` |

Status lines on the UART are clipped to 96 characters. The configuration `SDR` is millions of characters, and printing it would dominate the runtime.

## 7. SVF generation

The checked-in file is produced by recording a program operation against an SVF target in Vivado Hardware Manager. No cable and no board are required. The part is the Nexys A7-100T device, `xc7a100tcsg324-1`.

```tcl
open_hw_manager
connect_hw_server -url localhost:3121
create_hw_target nexys_a7_svf
open_hw_target [lindex [get_hw_targets -regexp .*/nexys_a7_svf] 0]
set dev [create_hw_device -part xc7a100tcsg324-1]
set_property PROGRAM.FILE {C:/path/to/target_design.bit} $dev
program_hw_devices $dev
write_hw_svf {C:/path/to/nexys_a7_01.svf}
close_hw_target
```

The header of the resulting file is a single-device Artix-7 sequence: `TRST OFF`, idle end states, `STATE RESET`, `STATE IDLE`, `FREQUENCY 1.00E+07 HZ`, zero chain padding, then the IDCODE, JPROGRAM, initialization, and configuration shifts. Later comments mark `config/start` and `config/status`.

`SIR 6 TDI (09)` is the 7-series IDCODE instruction. `SIR 6 TDI (0b)` is JPROGRAM. The 30,606,304-bit `SDR` is the configuration payload: 3,825,788 bytes of shift data, stored as ASCII hex, which is why the file is about 7.7 MB.

Before the file is embedded it is checked for the expected IDCODE, zero padding, a configuration shift of tens of millions of bits, and a complete startup and status trailer. Vivado writes the init delay as `RUNTEST 0.100000 SEC;`. The bundled `libxsvf` rejects a decimal point in that position. The file is rewritten as `RUNTEST 1E-1 SEC;`, which is the same 0.1 s.

The same asset is installed in all three applications:

```text
sw/nexys_a7/app_mb_svf_player/assets/nexys_a7_01.svf
sw/nexys_a7/app_mb_jtag_verifier/assets/nexys_a7_01.svf
sw/zcu102/app_svf_player/assets/nexys_a7_01.svf
```

Replacing the SVF without rebuilding leaves the previous payload in the ELF. The size printed at startup is the check.

## 8. Verification

### 8.1 Bring-up without a target

Before J10 is wired, the output pins can drive LEDs through 330 ohm to 1 kohm resistors. TDO is an input and does not get an LED. The LEDs are removed before a real target is connected.

| Command | Result with no target |
|---|---|
| `t` | Output nibble walks `1, 2, 4, 8, F, 0` with 300 ms between steps |
| `d` | Parser and pin callbacks run the short demo SVF. TDO mismatches are ignored. `rc` is 0 if the parser accepts the string |
| `p` | Fails at the IDCODE `SDR`. UART shows a TDO mismatch, then `rc=-1`, and the first failing TCK count plus the expected and sampled bits |

`p` without a target is a useful negative test. The parser got far enough to shift 32 data bits and compare them. It is not a sign that the SVF file or the GPIO path is broken.

### 8.2 Programming a target

The programmer is built and downloaded over its own USB-JTAG port. The console banner ends with the blob size, then the menu waits. `t` and `d` are run with J10 open. Outputs are driven low with `r`, LEDs are removed, and the four JTAG wires plus ground are connected. `p` is sent only after the target is powered.

Success is all of the following:

- `SVF playback finished with rc=0`
- A non-zero TDO check count, and no TDO mismatch line
- The target DONE LED is on
- The design that was baked into the SVF is the design now running on the target

A mismatch after a long run, with a large TCK count, means IDCODE and the init poll passed and a later compare failed. The usual causes are a target that lost power during the shift, another master on TMS or TCK, or an SVF generated for a different part. A mismatch on the first data shift is wiring, power, a second master on J6, a swapped TDI/TDO pair, or a device that is not an XC7A100T.

The final status shift compares a single masked bit (`MASK (08000000)`). A mismatch there means the device did not reach the expected status after startup, so `rc` is `-1` even if the long shift itself completed.

### 8.3 Waveform verifier

The Nexys A7 verifier is the counterpart of the ZCU102 player. It does not implement a TAP state machine of its own and it does not write a second SVF parser. It runs the same `libxsvf_play` over the same SVF bytes, with `pulse_tck` inverted:

| | ZCU102 player | Nexys A7 verifier |
|---|---|---|
| TCK | drives the pulse | waits for the pulse |
| TMS | drives the expected value | samples and compares |
| TDI | drives the expected value | samples and compares |
| TDO | samples and compares | drives the expected value |

Because `libxsvf` is deterministic, both instances walk the file in lockstep. On every clock the verifier receives the TMS and TDI values the player should be driving, and the TDO value the SVF says the target should return. Driving TDO lets the player's own TDO checks pass, which closes the return path.

The verifier detects TCK edges by polling the AXI GPIO input register from C. It needs real time between the player's falling edge and the player's TDO sample. The player's `d` command, at about 100 ms per edge, leaves that margin and is the bring-up pair. The player's `p` command, with zero edge delay, is faster than the poll loop, so the embedded configuration file is not verified this way. The demo SVF has no TDO fields, so a `d` run validates TCK, TMS, and TDI only.

Wiring is point to point and is not a straight ribbon. On the verifier, TCK, TMS, and TDI are inputs on JA7, JA8, and JA9, and TDO is an output on JA1. The verifier is armed before the player starts clocking. The first clock waits for TCK high and then for the falling edge, so an idle-low TCK is not mistaken for the first pulse.

## 9. Results

These are the outcomes the player and the checked-in SVF are built to produce. A bench log of one particular programming session is not stored in the repository. The pass and fail text is what the firmware prints, and the IDCODE and shift length are what `assets/nexys_a7_01.svf` contains.

| Check | Value |
|---|---|
| Device | One TAP, no chain padding |
| Instruction width | 6 |
| IDCODE | `0x03631093`, mask `0x0FFFFFFF` |
| Requested TCK | 10 MHz, not enforced by the player |
| Configuration shift | 30,606,304 bits |
| Embedded file size | 7,682,571 bytes (7,712,737 with CRLF line endings) |
| Recorded Nexys A7 ELF | `text` 7,747,420, `data` 1,624, `bss` 33,571,276 |

The `text` size tracks the SVF because `.incbin` places the file in `.rodata`. The `bss` size tracks the 32 MiB heap reservation. Both are expected for this asset.

A completed configuration reports:

```text
SVF playback finished with rc=0
TCK clocks: <large count>, TDI bits: <large count>, TDO checks: <count>
```

The clock count is dominated by the 30,606,304-bit shift plus the `RUNTEST` clocks (10,000 during init, 100,000 at startup, and the smaller sequences). Runtime is the cost of those GPIO transactions. The 10 MHz `FREQUENCY` command only produces the UART line `using GPIO bit-bang speed.`

## 10. Limitations

- TRST is not a pin. TAP reset still happens through TMS and TCK.
- The player will not discover extra devices. Padding is fixed in the SVF at zero.
- Command `p` cannot configure the FPGA that is executing the player. That download uses the board's own USB-JTAG, or the usual PS/PL programming path on the ZCU102.
- The GPIO path does not honor the SVF frequency. Configuration works and takes longer than a cable.
- The polling verifier can follow the slowed demo. It cannot follow a full-speed configuration shift.
- The loop-test SVF in the verifier, which would exercise TDO as well as TCK, TMS, and TDI, has no matching command on the current ZCU102 player.
- Replacing the SVF without rebuilding leaves the previous payload in the ELF.

## 11. Conclusion

A MicroBlaze system on a Nexys A7 and a Cortex-A53 system on a ZCU102 both play a Vivado configuration SVF through an AXI GPIO port and configure a second Nexys A7-100T. The software contract is small: `libxsvf` parses the file, and one callback writes TCK, TMS, and TDI and samples TDO. The same callback, inverted, lets a third board check the waveform against the file.

The design is sufficient for a single Artix-7 on a 3.3 V TAP. Bring-up is separated from programming: `t` and `d` prove the pins with no target, and `p` enforces every TDO compare, starting with the IDCODE. The cost of the approach is speed. Each bit is several register writes, and the 30.6 million bit configuration shift dominates the run.

## References

1. IEEE Std 1149.1, IEEE Standard for Test Access Port and Boundary-Scan Architecture.
2. Clifford Wolf, `libxsvf`, https://github.com/cliffordwolf/libxsvf.
3. Digilent, Nexys A7 FPGA Board Reference Manual.
4. AMD, Vivado Design Suite and Vitis embedded tools, 2025.1 / 2025.2 flows used by this repository.
5. AMD, 7 Series FPGAs Configuration User Guide, for the XC7A100T JTAG instructions used by the generated SVF (IDCODE, JPROGRAM, JSTART).
