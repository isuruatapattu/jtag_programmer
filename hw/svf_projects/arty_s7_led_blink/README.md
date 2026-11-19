# Arty S7 four-LED fill

`leb_blink` uses the existing 100 MHz clock on R2. `LED[3:0]` repeats
`0000 -> 0001 -> 0011 -> 0111 -> 1111 -> 0000`, holding each state for
50,000,000 clocks (0.5 seconds). The cycle lasts 2.5 seconds. Registers
initialize to zero at configuration; no reset toggle is needed. SW0 (`rst_n`,
H14) synchronously holds the LEDs off when low. Releasing it starts a full
0.5-second off interval. `STEP_CYCLES` must be positive.

| Port | Package pin | Connection |
|---|---|---|
| LED[0] | E18 | First monochrome LED |
| LED[1] | F13 | Second monochrome LED |
| LED[2] | E13 | Third monochrome LED |
| LED[3] | H15 | Fourth monochrome LED |
| programming_done | L17 | JA physical pin 1 |

All five outputs use LVCMOS33. `programming_done` is continuously high once
startup enables user I/O, even while the LED reset is low. It acknowledges
that this design is configured, not independent verification of its image,
flash contents, or clock operation.

## Connecting the programmer

Connect JA1 to a 3.3 V-compatible programmer input and connect board grounds.
Provide an external pull-down so the input has a defined low level while the
target is unconfigured. Target RTL cannot drive low before configuration.
Configuration-time pull-ups depend on PUDC_B; select and validate the external
pull-down against the actual board configuration and receiver thresholds.
See [AMD UG470](https://docs.amd.com/v/u/en-US/ug470_7Series_Config).

Synchronize this asynchronous input through two flip-flops in the programmer's
clock domain. For each programming attempt, clear the previous acknowledgement,
observe low after configuration is cleared, then accept a fresh high after
startup; a stale high is not evidence of a new programming completion. Keep
normal JTAG status/error checks. Receiver implementation is outside this project.

## Rebuild and simulate

From this directory, using a Vivado 2025.2 command environment:

```powershell
New-Item -ItemType Directory -Force build | Out-Null
Set-Location build
xvlog -sv ../arty_s7_led_blink.srcs/sources_1/new/leb_blink.sv ../tests/tb_leb_blink.sv
xelab tb_leb_blink -s led_test
xsim led_test -runall
vivado -mode batch -source ../build.tcl -log build.log -journal build.jou
vivado -mode batch -source ../generate_svf.tcl -log svf.log -journal svf.jou
```

The testbench checks step counts 1, 3 and 4, exact durations, repeated sequences,
startup without reset, synchronous reset during filling, and acknowledgement
through reset. Build outputs are `build/leb_blink.bit`, a routed checkpoint,
and timing, DRC and I/O reports. The in-memory build does not replace existing
Vivado project runs. The SVF script requires a local hw_server on port 3121;
it records a virtual single-device target and does not program physical hardware.
It updates `arty_s7_led_blink.svf` and converts the fractional RUNTEST delay to
exponential notation for the bundled libxsvf parser. Application asset copies
and firmware must be updated/rebuilt separately before using this new payload.

## Hardware acceptance

Program the new bitstream or SVF. Confirm LED 0 lights first, each state lasts
0.5 seconds, and all-off lasts 0.5 seconds. Measure JA1 during reprogramming:
it must be recognized low while configuration is cleared and high after startup.
Repeat with SW0 held low; LEDs stay off but JA1 still asserts. Confirm the
programmer observes a fresh acknowledgement on every attempt. These physical
checks require connected boards and suitable measurement equipment.

## Validation results

Vivado 2025.2 simulation passed all three step-count cases. Synthesis, placement,
routing and bitstream generation succeeded. DRC reported zero violations; routed
setup slack was 5.942 ns and hold slack was 0.209 ns. The I/O report confirmed all
five output pin mappings. The existing reset input and LED outputs have no external
I/O delay constraints, so these timing results cover the constrained internal paths.
Hardware measurements have not been performed.
