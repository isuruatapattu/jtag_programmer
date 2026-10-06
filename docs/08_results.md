# 08 Results

These are the outcomes the player and the checked-in SVF are built to produce. A bench log of one particular programming session is not stored in the repository. The pass/fail text below is what the firmware prints, and the IDCODE and shift length are what `assets/nexys_a7_01.svf` contains.

## SVF identity

| Check | Value in `nexys_a7_01.svf` |
|---|---|
| Device | One TAP, no chain padding |
| Instruction width | 6 |
| IDCODE | `0x03631093`, mask `0x0FFFFFFF` (XC7A100T, revision ignored) |
| Requested TCK | 10 MHz, not enforced by the player |
| Configuration shift | 30,606,304 bits |
| File size embedded by the player | 7,682,571 bytes (7,712,737 with CRLF line endings) |
| Recorded Nexys A7 ELF | `text` 7,747,420, `data` 1,624, `bss` 33,571,276 |

The `text` size tracks the SVF because `.incbin` places the file in `.rodata`. The `bss` size tracks the 32 MiB heap reservation. Both are expected for this asset. See [05 SVF generation](05_svf_generation.md).

## No target

| Command | Result |
|---|---|
| `t` | Output nibble walks `1, 2, 4, 8, F, 0` with 300 ms between steps |
| `d` | Parser and pin callbacks run the short demo SVF. TDO mismatches are ignored. `rc` is 0 if the parser accepts the string |
| `p` | Fails at the IDCODE `SDR`. UART shows `[SVF ERROR]` with `TDO mismatch`, then `rc=-1`, and the first failing TCK count plus the expected and sampled bits |

`p` without a target is a useful negative test. The parser got far enough to shift 32 data bits and compare them. It is not a sign that the SVF file or the GPIO path is broken.

## Target attached

Send `p` only after [07 Programming a Nexys A7](07_programming_nexys_a7.md). A completed configuration reports:

```text
SVF playback finished with rc=0
TCK clocks: <large count>, TDI bits: <large count>, TDO checks: <count>
```

There is no mismatch line. On the target, DONE is lit, and the bitstream that was recorded into the SVF is the one configured. The final status shift in the SVF compares a single masked bit (`MASK (08000000)`); a mismatch there means the device did not reach the expected status after startup, so `rc` is `-1` even if the long shift itself completed.

The clock count is dominated by the 30,606,304-bit shift plus the `RUNTEST` clocks (10,000 during init, 100,000 at startup, and the smaller sequences). Runtime is the cost of those GPIO transactions. The 10 MHz `FREQUENCY` command only produces the UART line `using GPIO bit-bang speed.`

## Limits that show up in the result

- TRST is not a pin. `TRST OFF` does not move a wire. TAP reset still happens through TMS and TCK.
- The player will not discover extra devices. Padding is fixed in the SVF at zero.
- Command `p` cannot configure the FPGA that is executing the player. That download has to use the board's own USB-JTAG (or, on the ZCU102, the usual PS/PL programming path).
- Replacing the SVF without rebuilding leaves the previous payload in the ELF. The size printed at startup is the check.
