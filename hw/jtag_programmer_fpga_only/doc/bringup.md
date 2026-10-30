# Hardware bring-up of the FPGA-only JTAG programmer

Everything below runs from `hw/jtag_programmer_fpga_only/`. Steps 1 and 2
need Vivado; the rest needs the Nexys A7 board, the target board and,
for step 6, an oscilloscope.

## Wiring (same as the MicroBlaze programmer)

| PMOD JA pin | Signal | Target JTAG |
|-------------|--------|-------------|
| JA1         | TCK    | TCK         |
| JA2         | TMS    | TMS         |
| JA3         | TDI    | TDI         |
| JA7         | TDO    | TDO         |
| JA5 / JA11  | GND    | GND         |

Both boards must use 3.3 V JTAG I/O. Keep the cable short.

## Controls and indicators

| Control       | Function |
|---------------|----------|
| BTNC          | Start: pass 1 (check whole stream, no JTAG activity), then pass 2 (program) |
| BTNU          | Abort; the target TAP is sent to Test-Logic-Reset |
| CPU_RESET     | Reset the programmer |
| SW[2:0]       | TCK limit: 0 = 10 MHz, 1 = 1 MHz, 2 = 5 MHz, 3 = 12.5 MHz, 4 = 16.7 MHz, 5 = 25 MHz, 6 = 100 kHz, 7 = 10 kHz |
| SW[13]        | Start once automatically after reset |
| SW[14]        | Skip pass 1 (saves about 1.3 s; a corrupt stream is then only detected at its end) |
| SW[15]        | Use the SW[2:0] frequency even if it is faster than the SVF `FREQUENCY` |

Without SW[15], TCK is the slower of the SW[2:0] setting and the SVF
`FREQUENCY` (the reference SVF asks for 10 MHz).

| LED      | Meaning |
|----------|---------|
| LD0      | Ready |
| LD1      | Busy |
| LD2      | Last run OK |
| LD3      | TDO mismatch (target answered differently than the SVF expects) |
| LD4      | Stream error: header, opcode, overrun, CRC, TCK count, argument or timeout |
| LD5      | Flash ID error (LD15..8 then show the JEDEC manufacturer byte) |
| LD6      | Aborted |
| LD7      | Pass 1 running |
| LD15..8  | Progress while busy; after an error, the status code (below) |

The USB-UART (115200 8N1) prints `JTAG FLASH OK 0x0000000000<JEDEC>` at
power-up and one line per run, for example `JTAG OK       0x0000000001d4b374`
(TCK count) or `JTAG ERR TDO  0x<TCK index of the first mismatch>`.

| Code | UART text | Meaning |
|------|-----------|---------|
| 1    | OK        | Success |
| 2    | ERR TDO   | TDO mismatch; info = TCK index |
| 3    | ERR HDR   | Bad JBIN header (no flash data at 0x400000?) |
| 4    | ERR OPC   | Unknown opcode, or END not at the end |
| 5    | ERR OVR   | Opcode runs past the payload |
| 6    | ERR CRC   | Payload CRC mismatch; info = computed CRC |
| 7    | ERR TCK   | TCK count differs from the header |
| 8    | ABORT     | BTNU pressed |
| 9    | ERR ARG   | Invalid opcode argument |
| 10   | ERR FLID  | Flash JEDEC ID not accepted; info = JEDEC ID |
| 11   | ERR TOUT  | Flash stream stalled |

## Steps

1. **Simulation and build.**
   `vivado -mode batch -source sim/run_sim.tcl` (all tests must pass, with the
   XPM FIFO), then `vivado -mode batch -source scripts/build.tcl`. The build
   stops if timing fails or a pin register is not in its IOB.

2. **Flash image with the IDCODE-only stream.**
   ```
   python tools/svf2jbin.py sim/svf/idcode.svf build/idcode.jbin
   vivado -mode batch -source scripts/make_flash.tcl -tclargs build/idcode.jbin program
   ```
   Power-cycle the board (JP1 set to QSPI boot).

3. **Flash read and JEDEC check.** Expect LD0 on and the UART line
   `JTAG FLASH OK 0x0000000000012018` (S25FL128S; other vendors print other
   IDs, any 64 Mbit or larger part is accepted). LD5 means the flash did not
   answer: check JP1, the bitstream, and the flash part.

4. **Pass 1 alone.** With the target disconnected, press BTNC. Pass 1 must
   pass (LD7 blinks briefly); pass 2 then ends with `ERR TDO` because no
   target answers. This proves header, CRC and stream decoding on hardware.

5. **IDCODE at 1 MHz and 10 MHz.** Connect and power the target. The
   IDCODE SVF asks for 1 MHz: SW[15:0] all off, press BTNC, expect LD2 and
   `JTAG OK 0x...3b` (59 TCK). Then SW[15] on with SW[2:0] = 0 (10 MHz) and
   repeat.

6. **Scope check at 10 MHz** (IDCODE stream with SW[13] on, so it repeats on
   every reset): TCK high and low 50 ns each, TMS/TDI change on the falling
   TCK edge, TDO from the target settles well before the next falling edge,
   no ringing that crosses the input thresholds on TCK at the target.

7. **Full programming at 1 MHz, then 10 MHz.**
   ```
   python tools/svf2jbin.py ../../sw/nexys_a7/app_mb_svf_player/assets/nexys_a7_01.svf build/target.jbin
   vivado -mode batch -source scripts/make_flash.tcl -tclargs build/target.jbin program
   ```
   SW[2:0] = 1 (1 MHz limit): BTNC, expect `JTAG OK 0x0000000001d4b374`
   (30,716,788 TCK) after about 32 s. Then SW[2:0] = 0 (10 MHz, as requested
   by the SVF): about 1.3 s for pass 1 plus 3.2 s for pass 2. Success means
   no TDO mismatch, the final status read (DONE bit, `MASK 08000000`) passed,
   and the target design starts.

8. **Faster TCK (optional).** SW[15] on and SW[2:0] = 3, 4, then 5
   (12.5, 16.7, 25 MHz), watching TCK and TDO on the scope. Keep the fastest
   setting that passes repeatedly with margin. Above 10 MHz the flash read
   rate (3.07 MB/s) is the limit: TCK pauses briefly while the FIFO refills,
   which is harmless.

## If something fails

- `ERR TDO` at a small TCK index: wiring, target power, or TCK too fast for
  the cable; retry at 1 MHz (SW[2:0] = 1).
- `ERR TDO` only at the final status read: the target received the
  bitstream but did not start; check that the SVF matches the target device.
- `ERR CRC` or `ERR HDR`: the flash data does not match the JBIN; rerun
  `make_flash.tcl` (it verifies the MCS and the flash contents).
- `ERR TOUT`: the flash stopped delivering data; check JP1 and the STARTUPE2
  clock (CCLK) on the scope.
