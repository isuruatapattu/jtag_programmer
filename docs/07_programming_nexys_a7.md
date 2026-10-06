# 07 Programming a Nexys A7

This is the path that configures a target Nexys A7-100T from the embedded SVF. The programmer is either the MicroBlaze design or the ZCU102 design. The target is a second Nexys A7. Pin names below use JA; on the ZCU102 use J55.1, J55.3, J55.5, and J55.7 for TCK, TMS, TDI, and TDO.

## 1. Build and download the programmer

1. Open `hw/nexys_a7_jtag_programmer/nexys_a7_jtag_programmer.xpr` (or the ZCU102 project) and confirm the bitstream is current. [03 Vivado design](03_vivado_design.md) lists the IP and the address map.
2. Build the matching programmer:
   - Nexys A7 application `sw/nexys_a7/app_mb_svf_player`, against platform `sw/nexys_a7/ws_20260819/pf_nexys_a7`
   - ZCU102 application `sw/zcu102/app_svf_player`, against platform `sw/zcu102/ws_20260819/pf_zynq`
3. Build the platform, then the SVF player. If the SVF asset changed, follow [05 SVF generation](05_svf_generation.md) first.
4. Program the programmer FPGA with its own bitstream and run the player ELF. On the Nexys A7 that download uses J6 on the programmer, not J10 on the target.

## 2. Open the console

| Board | Port | Baud |
|---|---|---|
| Nexys A7 programmer | USB-UART on J6 | AXI UART Lite rate; board preset is 9600 8N1 |
| ZCU102 programmer | PS UART | 115200 8N1 |

The banner ends with the blob size. For the SVF in the tree that size is 7,682,571 bytes, or 7,712,737 bytes with CRLF line endings. Then the menu waits at `Input:`.

## 3. Prove the pins before connecting the target

Leave J10 unconnected.

1. Send `t`. The four output LEDs, if fitted, walk one bit at a time, then all on, then off. See [02 Hardware setup](02_hardware_setup.md) for the resistor.
2. Send `d`. TCK, TMS, and TDI should move in a slow TAP pattern. This command is allowed to finish with no device attached.
3. Send `r` so the outputs are low.
4. Remove any LEDs from TCK, TMS, and TDI.

## 4. Wire and power the target

```text
Programmer TCK -> target J10 TCK
Programmer TMS -> target J10 TMS
Programmer TDI -> target J10 TDI
Programmer TDO <- target J10 TDO
GND            <-> GND
```

On the target:

- JP3 selects the barrel jack, and the barrel supply is on.
- The PROG USB plug (J6) is out, so the onboard USB-JTAG circuit is not a second master on the same TAP.
- JP1 is in the JTAG position.
- The board is already out of reset before you send `p`.

Do not connect a 3.3 V pin between the boards. Do not run `p` against the programmer's own JTAG port.

## 5. Play the SVF

Send `p`. The console prints `Starting embedded SVF playback.`, the blob address and size, then the 10 MHz frequency note. Short `[SVF]` lines follow. They stay short on purpose.

Leave the serial session open and leave both boards powered until the player prints `SVF playback finished`. A full configuration is one shift of 30,606,304 bits, and each bit is several AXI GPIO writes, so this is much slower than the few seconds a USB-JTAG download takes.

## 6. Decide the result

Success is all of the following:

- `SVF playback finished with rc=0`
- A non-zero `TDO checks` count, and no `TDO mismatches` line
- The target DONE LED is on
- The design that was baked into the SVF is the design now running on the target

Failure during the IDCODE shift, with no target or with TDO floating, looks like:

```text
[SVF ERROR] ... TDO mismatch
SVF playback finished with rc=-1
TDO mismatches: 1, first at TCK <n> expected <bit> actual <bit>
```

That result is correct for an open TDO. It is also the result for a wrong device, a swapped TDI/TDO pair, a target that is off, or J6 still driving the TAP. [09 Troubleshooting](09_troubleshooting.md) is the order to check those.

After a failed attempt, send `r`, fix the setup, and send `p` again. The player does not need to be rebooted between attempts unless the GPIO initialization itself failed (`JA GPIO init failed` hangs).
