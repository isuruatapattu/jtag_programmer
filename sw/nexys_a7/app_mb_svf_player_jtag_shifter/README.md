# app_mb_svf_player_jtag_shifter

This is a copy of `app_mb_svf_player` that plays the embedded SVF through the hardware JTAG shifter at `0x44A0_0000`. It needs the `hw/nexys_a7_jtag_programmer_jtag_shifter` bitstream and `platform_jtag_shifter`. The original app is not modified.

## What changed from `app_mb_svf_player`

- **`external/libxsvf`** (private copy):
  - `libxsvf.h` adds `struct libxsvf_shift` and an optional `shift_block` host callback.
  - `svf.c` `bitdata_play()` offers each whole scan to that callback before the per-bit loop. The callback returns 0 (done), -1 (TDO mismatch) or 1 (not handled, so the scan falls back to per-bit `pulse_tck`).
  - Hosts that leave `shift_block` NULL behave exactly as before.
- **`jtag_shifter.h`**: register map and small `Xil_In32`/`Xil_Out32` helpers.
- **`svf_player.c`**:
  - `mb_svf_shift_block()` sends each SIR/SDR scan (and any HIR/TIR/HDR/TDR headers) as 32-bit DATA words. It compares TDO a word at a time under MASK, and keeps fewer than 256 captured words unread. Scans with SMASK or RMASK go bit by bit.
  - In shifter mode:
    - `pulse_tck` sends a one-bit command.
    - `udelay` clocks TMS in 32-bit words.
    - `FREQUENCY` sets `CLKDIV = ceil(100 MHz / 2f)`. The default is 5, which gives 10 MHz TCK.
  - The elapsed time comes from the shifter `CYCLES` counter and is printed after each run, for both the shifter and the GPIO paths.
  - At startup the app reads the shifter `ID` register and prints whether the shifter was found.

## Menu

| Key | Action |
|---|---|
| `p` | Play the embedded SVF through the JTAG shifter (new default) |
| `g` | Play the embedded SVF by AXI GPIO bit-banging (the old `p`, for comparison) |
| `s` | GPIO bit-bang with a slow edge delay |
| `j`, `i`, `d`, `t`, `r` | Unchanged (probe, TDO read, LED demo, LED test, reset). These always use GPIO |

The shifter is in bypass whenever an SVF is not playing through `p`. All GPIO commands therefore drive the pins exactly as in the original app.

## Build

After `hw/nexys_a7_jtag_programmer_jtag_shifter/create_project.tcl` has written `design_1_wrapper.xsa`:

```sh
cd sw/nexys_a7
vitis -s create_platform_jtag_shifter.py
```

This creates `platform_jtag_shifter` (standalone, `microblaze_0`) and builds this app. `src/app.yaml` holds an absolute `domain_path`. If the workspace is not at that path, update it, or re-select the platform in Vitis.

The embedded SVF is the same as in the original app; it is set in `src/UserConfig.cmake` and `svf_blob.S`.

## Host model test

`test/host` builds `svf_player.c` and libxsvf with the host `gcc`. It links them against stub Xilinx headers and a C model of the AXI GPIO, the shifter registers, the pin mux and a TAP. The TAP has a 6-bit IR, IDCODE `0x03631093`, BYPASS, and a 10000-bit loopback DR.

Every SVF is played through both the GPIO path and the shifter path. The test checks that both paths give the same TMS/TDI value at every TCK rising edge, and the same final TAP state, return code, TDO check count and first mismatch position. It also checks that the RX FIFO never overflows.

```sh
sh test/host/run_host_test.sh          # Linux
# Windows: run the commands in test/host/run_host_test.ps1
```

The run prints `HOST TEST: PASS`. The model does not cover AXI timing or FIFO back-pressure; the RTL testbench in `hw/ip/jtag_shifter/sim` covers those.

## Hardware test

1. Program the new bitstream and run the app. The banner must show the shifter as found.
2. Bypass check: `t`, `r`, `i`, `j` and `d` behave as in the original app.
3. With no target on JA, press `p`. It must stop at the first TDO check with a mismatch, and must not hang.
4. With the target on JA, press `p`. It must finish with `rc=0` and 0 mismatches, and the target must configure.
5. Press `g` with the same target. Compare the `Elapsed:` lines for `p` and `g`; expect a few seconds for `p` against tens of seconds for `g`.
6. If `p` shows TDO mismatches that `g` does not, check the TDO margin at CLKDIV 5 (see the spec). Retry with a lower SVF `FREQUENCY` to raise CLKDIV.
