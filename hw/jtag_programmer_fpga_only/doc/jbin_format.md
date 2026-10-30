# JBIN v1 - binary JTAG command stream

JBIN is the format the FPGA-only programmer replays. It is produced offline from
an SVF file by `tools/svf2jbin.py` and stored in the QSPI flash at
`0x00400000` (see `scripts/make_flash.tcl`).

Every TAP state walk is already resolved into explicit TMS bits, so the
hardware never parses SVF text and never tracks TAP states.

## Conventions

- All multi-byte integers are little-endian.
- Bit streams are LSB-first: bit 0 of the first data byte is the first bit on
  the wire. For a scan this means bit 0 of the SVF hex value goes out first,
  exactly like libxsvf.
- One "clock" is one TCK cycle: falling edge (TMS/TDI update), low phase,
  rising edge (target samples TMS/TDI), high phase. TCK idles high.
- TDO launched by the target on a falling edge is sampled at the end of that
  TCK cycle (just before the next falling edge).
- "TDI held" means the TDI pin keeps the value driven by the previous clock.
  This matches libxsvf `tdi = -1`. The pin is 0 after reset.

## Header (32 bytes)

| Offset | Type    | Field           | Value / meaning                                  |
|-------:|---------|-----------------|--------------------------------------------------|
| 0      | u8[4]   | magic           | `"JBIN"` (`4A 42 49 4E`)                         |
| 4      | u16     | version         | `1`                                              |
| 6      | u16     | flags           | `0` (reserved, must be 0)                        |
| 8      | u32     | payload_len     | Number of payload bytes after the header         |
| 12     | u32     | payload_crc32   | CRC-32 of the payload bytes                      |
| 16     | u64     | total_tck       | Exact number of TCK cycles in the payload        |
| 24     | u32     | reserved        | `0`                                              |
| 28     | u32     | header_crc32    | CRC-32 of header bytes 0..27                     |

CRC-32 is the standard reflected CRC (polynomial `0xEDB88320`, init
`0xFFFFFFFF`, final XOR `0xFFFFFFFF`), identical to Python `zlib.crc32`.

The hardware rejects the stream before any JTAG activity when the magic,
version, flags, reserved field or header CRC is wrong, or when `payload_len`
does not fit in the flash region.

## Payload opcodes

The payload is a sequence of opcodes. Each opcode is one byte followed by its
arguments. The last payload byte must be `END`.

| Code   | Name      | Arguments                         | Effect |
|--------|-----------|-----------------------------------|--------|
| `0x01` | `TMS`     | `n:u8` (1..255), `bits[ceil(n/8)]`| `n` clocks. TMS = next bit of `bits`, TDI held. Used for all TAP state walks. |
| `0x02` | `SHIFT`   | `n:u32` (>= 1), `flags:u8`, data  | `n` clocks of scan data, see below. |
| `0x03` | `RUNCLK`  | `n:u32` (0 allowed)               | `n` clocks with TMS = 0, TDI held. |
| `0x04` | `WAIT_US` | `n:u32` (0 allowed)               | Wait `n` microseconds with TCK stopped high. |
| `0x05` | `SET_DIV` | `d:u16` (>= 2)                    | TCK half period in 100 MHz system clocks requested by the SVF `FREQUENCY` command. TCK = 100 MHz / (2 d). |
| `0x06` | `TRST`    | `v:u8`                            | No operation (no TRST pin). Kept for traceability. |
| `0xFF` | `END`     | none                              | End of stream. Must be the last payload byte. |

Any other opcode is a format error.

### SHIFT

`flags`:

- bit 0 `last_tms`: TMS = 1 on the last bit (leaves Shift-DR/IR to Exit1).
  TMS is 0 on all other bits.
- bit 1 `compare`: TDO is checked under a mask.
- bits 7..2: must be 0.

Data, in groups of 8 bits (the last group may be partial; unused high bits are
0):

- `compare = 0`: one byte per group: `tdi`.
- `compare = 1`: three bytes per group, interleaved: `tdi`, `tdo`, `mask`.

For bit `b` of a group: TDI = `tdi[b]`; if `compare` and `mask[b]` = 1, the
sampled TDO must equal `tdo[b]`. A mismatch is sticky. The hardware finishes
the current opcode, then clocks five TMS = 1 cycles to Test-Logic-Reset and
reports the 0-based TCK index of the first failing bit.

## Frequency handling in hardware

The effective half period is `max(d_file, d_switch)`, where `d_file` comes
from `SET_DIV` (default 5 = 10 MHz) and `d_switch` from the board switches. A
switch override can ignore `d_file`. See `rtl/top.sv`.

## Size of the reference bitstream

For `nexys_a7_01.svf` (XC7A100T), the stream is about 3.83 MB, almost all of it
one TDI-only `SHIFT` of 30,606,304 bits.
