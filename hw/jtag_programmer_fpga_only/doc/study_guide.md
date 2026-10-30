# Study guide: the FPGA-only JTAG programmer RTL

This guide walks you through `hw/jtag_programmer_fpga_only/rtl/` in an order
that builds understanding step by step. It assumes you can read
SystemVerilog comfortably (FSMs, `always_ff`/`always_comb`, valid/ready),
but have not yet turned a MicroBlaze software application into pure logic.

Each step lists the files to open, what to look for, how it maps to the old
MicroBlaze player (`sw/nexys_a7/app_mb_svf_player/svf_player.c` with
libxsvf), and a few self-check questions with answers.

---

## Part A: the steps at a glance

| Step | Topic | Main files |
|-----:|-------|------------|
| 1 | Understand what the MicroBlaze player actually did per TCK | `sw/nexys_a7/app_mb_svf_player/svf_player.c` |
| 2 | Understand the conversion idea: move all interpretation offline | `tools/svf2jbin.py`, `doc/architecture_report.md` §1–2 |
| 3 | Learn the JBIN "instruction set" (the program format) | `doc/jbin_format.md`, `tools/jbin_common.py` |
| 4 | Read the top level and the design rules (one clock, reset, debounce, IOB, tri-state) | `rtl/top.sv`, `rtl/reset_gen.sv`, `rtl/debounce.sv`, `constraints/top.xdc` |
| 5 | Fetch stage: reading the SPI flash | `rtl/spi_flash_reader.sv`, `rtl/flash_sck_startup.sv` |
| 6 | Buffer stage: the byte FIFO and its flow control | `rtl/byte_fifo.sv` |
| 7 | Decode stage, part 1: header, CRC, opcode and argument fetch | `rtl/jbin_decoder.sv`, `rtl/crc32.sv` |
| 8 | Decode stage, part 2: expanding opcodes into per-TCK work items | `rtl/jbin_decoder.sv` |
| 9 | Execute stage: the JTAG pin engine and TDO compare | `rtl/jtag_engine.sv` |
| 10 | TCK frequency selection | `rtl/tck_rate_selector.sv` |
| 11 | Error handling, abort and the watchdog inside the decoder | `rtl/jbin_decoder.sv` |
| 12 | System control: two passes, LEDs, UART | `rtl/top_ctrl.sv`, `rtl/uart_tx_status.sv` |
| 13 | Trace one complete run from power-up to "JTAG OK" | all of the above |
| 14 | Confirm your understanding with the simulations and tools | `sim/`, `tools/jbin_model.py` |

The pipeline you will build up in your head:

```text
QSPI flash --> spi_flash_reader --> byte_fifo --> jbin_decoder --> jtag_engine --> JA pins
 (program)        (fetch)          (prefetch)      (decode)         (execute)
                                                      ^                  |
                     top_ctrl (sequencing, LEDs, UART) +---- idle/err ---+
```

---

## Part B: the steps in detail

### Step 1: What the MicroBlaze player did

**Goal:** know exactly which work the software performed, so you can see
where each piece went in the RTL.

**Read:** `sw/nexys_a7/app_mb_svf_player/svf_player.c`, functions
`mb_svf_setup`, `mb_svf_pulse_tck`, `mb_svf_udelay`, `mb_svf_getbyte`,
`mb_svf_set_frequency`, `mb_svf_set_trst`.

**What happens there:**

- libxsvf parses SVF *text* at run time. It pulls one character at a time
  through `mb_svf_getbyte` from the SVF blob in DDR, tracks the TAP state,
  and allocates buffers for whole SVF statements on the heap (32 MiB is
  reserved for the 30.6 Mbit configuration SDR).
- For every single TCK, libxsvf calls
  `mb_svf_pulse_tck(tms, tdi, tdo, rmask, sync)`, which:
  1. sets TMS and, if `tdi >= 0`, TDI in a shadow register (`tdi = -1`
     means "keep the previous TDI value"),
  2. writes the GPIO three times: TCK = 1, TCK = 0, TCK = 1,
  3. reads TDO through GPIO if `tdo >= 0` and compares it; on a mismatch it
     records the first failing clock and returns -1, which makes libxsvf
     stop.
- `mb_svf_udelay(usecs, tms, num_tck)` clocks `num_tck` cycles and then
  sleeps.
- `mb_svf_set_frequency` only prints the requested frequency; the GPIO
  bit-bang speed is whatever the CPU achieves.
- `mb_svf_set_trst` does nothing (there is no TRST pin).

**Key point:** each TCK costs a software call plus three AXI GPIO writes and
often one read. That is why `p` mode takes about 30–40 s.

**Mapping table (keep this open while reading the RTL):**

| MicroBlaze / libxsvf | FPGA-only RTL |
|----------------------|---------------|
| SVF text parsing, TAP state tracking, `HIR/TIR/HDR/TDR` handling | `tools/svf2jbin.py` on the host, before anything runs |
| SVF blob in DDR, `mb_svf_getbyte` | JBIN in QSPI flash at 0x400000, `spi_flash_reader` + `byte_fifo` |
| One `pulse_tck(tms, tdi, tdo, ...)` call | One *work item* from `jbin_decoder` to `jtag_engine` |
| `tdi = -1` (keep TDI) | `e_hold = 1` |
| `tdo >= 0` compare | `e_chk = 1`, `e_exp` = expected bit |
| `return -1` on the first mismatch | Sticky `err` + `err_tck` in the engine, checked at the next opcode boundary |
| `udelay(usecs, tms, num_tck)` | `RUNCLK n` (TMS = 0) followed by `WAIT_US us` |
| `set_frequency` (ignored) | `SET_DIV d` opcode, really applied through `div_file` and `half` |
| `set_trst` (no-op) | `TRST` opcode, decoded and ignored |
| `clock_count` | `tck_issued` (decoder), `tck_count` (engine) |
| UART menu and `xil_printf` | Buttons, switches, LEDs, `uart_tx_status` |
| `rc` value and printed messages | 4-bit status codes plus a 64-bit info word |

**Self-check**

- *Q: In the software, what does `tdi = -1` mean, and what is the RTL
  equivalent?*
  A: Keep the TDI pin at its previous value. In RTL it is `item_hold = 1`,
  so `jtag_engine` does not update `tdi_q`.
- *Q: Which libxsvf callback had no effect on the pins in the MicroBlaze
  design but does in the RTL?*
  A: `set_frequency`. In the RTL it becomes `SET_DIV`, which changes the
  TCK half period.

---

### Step 2: The conversion idea

**Goal:** understand *why* the hardware is shaped the way it is. This is the
part that is new if you have only written RTL from a spec, not from
software.

**Read:** the docstring at the top of `tools/svf2jbin.py`, the `Emitter`
class in the same file, and `doc/architecture_report.md` sections 1 and 2.

**The principle:** separate what is known before run time from what is
only known at run time.

- Known before run time: the SVF text, every TAP state transition, every
  TDI bit, every expected TDO bit and mask, every clock count and wait.
- Only known at run time: the actual TDO value from the target, the user's
  buttons and switches, and the flash timing.

So everything in the first group is computed once on the PC by
`svf2jbin.py`. It ports libxsvf's TAP walker (`tap_walk_bits`, a port of
`libxsvf_tap_walk`) and SVF semantics, and writes the result as a flat
binary program. The hardware only has to:

1. stream bytes,
2. decode seven opcodes,
3. turn each opcode into a sequence of single-clock work items,
4. drive pins with exact timing and compare TDO.

**General recipe you can reuse for other MicroBlaze-to-RTL conversions:**

1. Find the innermost loop of the software (here `pulse_tck`). That is
   what the execution unit must do in hardware.
2. List the decisions the software makes and ask for each one: does it
   depend on run-time data? If not, move it to a host tool.
3. Design a binary format that is trivial to decode: fixed field widths,
   little-endian, length-prefixed, no text, no pointers, no branches.
4. Build a stream pipeline: fetch → buffer → decode → execute, with
   valid/ready between stages so any stage can stall without losing data.
5. Replace software return codes with a fixed error FSM path and numeric
   status codes.
6. Keep a software reference model of the hardware (`tools/jbin_model.py`)
   and check the RTL and the converter against it, and the converter against
   the original software (`tools/golden/run_golden.py` compares against
   libxsvf).

**Consequence:** the program has no jumps, no loops and no registers. The
"program counter" is just the flash read address, which only increments.
Repetition is a count (`SHIFT n`, `RUNCLK n`).

**Self-check**

- *Q: Why does the hardware never need to know which TAP state the target
  is in?*
  A: `svf2jbin.py` has already turned every state walk into explicit TMS
  bits (`TMS` opcodes, and the `last_tms` flag of `SHIFT`). The only
  exception is the error path, which clocks five TMS = 1 cycles; that
  reaches Test-Logic-Reset from any state.

---

### Step 3: The JBIN instruction set

**Goal:** be able to read a JBIN byte stream by hand. Everything in the
decoder follows from this format.

**Read:** `doc/jbin_format.md` completely, then `Emitter.shift`,
`Emitter._flush_tms` and `pack_header` in the tools.

**Conventions:**

- Multi-byte integers are little-endian.
- Bit streams are LSB-first: bit 0 of the first data byte goes out first.

**Header (32 bytes):**

| Offset | Field | Checked by the decoder in `D_HCHK` |
|-------:|-------|-----------------------------------|
| 0 | magic `"JBIN"` | must be `0x4E49424A` as a little-endian u32 |
| 4 | version | must be 1 |
| 6 | flags | must be 0 |
| 8 | payload_len | must be non-zero and ≤ `MAX_PAYLOAD` (0xBFFFE0) |
| 12 | payload_crc32 | compared at the end of the payload |
| 16 | total_tck (u64) | compared with the number of clocks issued at the end |
| 24 | reserved | must be 0 |
| 28 | header_crc32 | CRC-32 of bytes 0..27, must match |

**Opcodes:**

| Code | Name | Argument bytes after the opcode | Then |
|------|------|---------------------------------|------|
| `01` | TMS | `n` (u8, 1..255) | `ceil(n/8)` bytes of TMS bits; TDI held |
| `02` | SHIFT | `n` (u32, ≥ 1), `flags` (u8) | data groups, see below |
| `03` | RUNCLK | `n` (u32, 0 allowed) | `n` clocks with TMS = 0, TDI held |
| `04` | WAIT_US | `n` (u32, 0 allowed) | wait with TCK high |
| `05` | SET_DIV | `d` (u16, ≥ 2) | TCK half period in 10 ns units |
| `06` | TRST | `v` (u8) | no operation |
| `FF` | END | none | must be the last payload byte |

`SHIFT` flags: bit 0 = `last_tms` (TMS = 1 on the last bit only), bit 1 =
`compare`, bits 7..2 must be 0. Data per group of 8 bits: one byte (`tdi`)
when not comparing, three bytes (`tdi`, `tdo & mask`, `mask`) when comparing.

**Worked examples** (hand-encoded from the rules above):

```text
01 05 1F                     TMS, 5 clocks, TMS bits 1,1,1,1,1 (bit 0 first)
02 06 00 00 00 01 09         SHIFT 6 bits, last_tms = 1, no compare, TDI = 0x09
03 10 27 00 00               RUNCLK 10000 (0x2710)
04 A0 86 01 00               WAIT_US 100000 (0x186A0) = 100 ms
05 05 00                     SET_DIV 5 -> 100 MHz / (2*5) = 10 MHz
FF                           END
```

A 32-bit compare shift has 4 groups, so it carries `4 × 3 = 12` data bytes
after its 6 header bytes (`02 20 00 00 00 03`; flags `03` = `last_tms` and
`compare`).

**Self-check**

- *Q: In a TDI-only SHIFT of 10 bits, how many data bytes follow, and where
  is bit 9?*
  A: Two bytes. Bit 9 is bit 1 of the second byte.
- *Q: Why does the compare data store `tdo & mask` instead of raw `tdo`?*
  A: So `e_exp` is 0 wherever the mask is 0. The decoder also ANDs again
  (`e_exp = g_msk & g_tdo`), and it only checks bits where `e_chk = mask = 1`.

---

### Step 4: Top level and the design rules

**Goal:** know the module boundaries and the rules that hold everywhere,
so later files read easily.

**Read:** `rtl/top.sv`, `rtl/reset_gen.sv`, `rtl/debounce.sv`, and the pin
section of `constraints/top.xdc`.

**Module tree:**

```text
top
├── reset_gen
├── debounce × 8   (BTNC, BTNU, SW_AUTO, SW_SKIP, SW_OVR, SW_DIV[2:0])
├── spi_flash_reader
│   └── flash_sck_startup (STARTUPE2)
├── byte_fifo
├── jbin_decoder
│   └── crc32
├── tck_rate_selector
├── jtag_engine
├── top_ctrl
└── uart_tx_status
```

**Rules that apply to the whole design:**

1. **One clock.** Everything runs on `CLK100MHZ`. The flash SCK and the
   JTAG TCK are *data* outputs of registers, not clocks. There are no clock
   domain crossings and no generated clocks. When you see "TCK" in the RTL,
   think "a register bit that toggles".
2. **Synchronous active-high reset.** `reset_gen` holds `rst` high for 31
   cycles after configuration (a power-on counter with an initial value)
   and whenever `CPU_RESETN` is low (two `ASYNC_REG` synchronizer
   flip-flops).
3. **Asynchronous inputs are synchronized.** Buttons and switches go
   through `debounce`: two flip-flops, then `level` only follows the input
   after it has been stable for `STABLE_CYCLES` (1,000,000 = 10 ms).
   `rise` is a one-cycle pulse when `level` goes high. BTNC uses `rise`
   (start is an event); BTNU and the switches use `level`.
4. **IOB registers on timing-critical pins.** `tck_q`, `tms_q`, `tdi_q`,
   `tdo_q` in the engine and `cs_q`, `mosi_q`, `miso_q` in the reader carry
   `(* IOB = "TRUE" *)`, and the XDC repeats `IOB TRUE`. Pin timing is then
   fixed by the silicon, so the XDC can use `set_false_path` on these
   ports.
5. **JTAG pins are tri-stated when not playing.** In `top.sv`:
   `JA_TCK = jtag_oe ? tck : 1'bz` (same for TMS, TDI). The XDC adds
   `PULLUP TRUE`. Only pass 2 drives the target.
6. **QSPI DQ2/DQ3 are tied high** (write protect off, HOLD/RESET inactive).
   Only single-I/O SPI on DQ0/DQ1 is used.

**Pins and controls (from the header comment of `top.sv`):**
JA1 = TCK, JA2 = TMS, JA3 = TDI, JA7 = TDO. BTNC = start, BTNU = abort,
`CPU_RESETN` = reset, SW[2:0] = TCK limit, SW13 = auto-start once after
reset, SW14 = skip pass 1, SW15 = switches override the file's TCK rate.

**Top-level parameters** (overridden in simulation to keep runs short):
`DEBOUNCE_CYCLES`, `FIFO_XPM` (1 = Xilinx XPM FIFO, 0 = inferred RAM),
`TIMEOUT_CYCLES` (stream watchdog, 50,000,000 = 0.5 s),
`UART_CLK_PER_BIT` (868 = 115200 baud).

**Self-check**

- *Q: Why is it safe to `set_false_path` on `JA_TCK` in the XDC?*
  A: The output register sits in the IOB, so its clock-to-pad delay is
  fixed and short, and TCK itself is at most 25 MHz with ≥ 20 ns between
  edges. No STA-driven placement is needed.
- *Q: Which buttons/switches are used as levels, and which as an edge?*
  A: BTNC as an edge (`rise`); BTNU, SW13, SW14, SW15 and SW[2:0] as levels.

---

### Step 5: Fetch stage — the SPI flash reader

**Goal:** understand how the program bytes get from the flash into the
FPGA, and why the first commands look odd.

**Read:** `rtl/flash_sck_startup.sv`, then `rtl/spi_flash_reader.sv`.

**5.1 Getting at the flash clock.** On 7-series parts CCLK (the flash
clock pin) is dedicated. User logic can only drive it through
`STARTUPE2.USRCCLKO`. `flash_sck_startup` instantiates `STARTUPE2` with
`USRCCLKTS = 0` (drive CCLK), `KEYCLEARB = 1` and DONE left alone. Its
`EOS` output (end of startup) tells the reader when the flash may be used.
The first three `USRCCLKO` edges after configuration do not reach the pin.

**5.2 State machine:**

```text
S_EOS ──EOS──> S_DUMMY ──8 SCK, CS high──> S_GAP
S_GAP ──(JEDEC not read)──> S_CSLOW ──> S_XFER ──last bit──> S_END ──> S_GAP
S_GAP ──(JEDEC done)──> S_IDLE ──stream_en && fifo_room──> S_CSLOW ...
S_CSLOW / S_XFER ──stream_en dropped during a READ──> S_GAP
```

1. `S_EOS`: wait for `eos`.
2. `S_DUMMY`: 8 SCK cycles with CS high, so the 3 swallowed edges do not
   matter.
3. `S_GAP`: CS high for `GAP_CYCLES` = 8 clocks (CS high time between
   commands). Then either issue the JEDEC ID command (first time only) or
   go to `S_IDLE`.
4. JEDEC ID: command `0x9F` (8 bits out) then 24 bits in. In `S_END`,
   `id_ok` is set if the manufacturer byte `jedec_id[23:16]` is not 0x00
   or 0xFF and the capacity byte `jedec_id[7:0]` is in 0x17..0x20.
   `id_done` stays 1 from then on.
5. `S_IDLE`: when `stream_en` is high and the reader is not yet `running`,
   latch `addr <= start_addr` and set `running`. Then, each time
   `fifo_room` is 1, issue `0x03 <24-bit addr>` and read `BLOCK_BYTES`
   (256) bytes.
6. `S_END`: for a READ, `addr += 256`. Then back to `S_GAP`.
7. Whenever `stream_en` is 0, `running` is cleared, so the next rise of
   `stream_en` restarts at `start_addr` (0x400000). That is how each pass
   restarts from the beginning of the JBIN.

**5.3 Bit timing (SPI mode 0, SCK = 25 MHz).** One bit takes four system
clocks, phases `ph = 0..3`:

```text
ph       0      1      2      3      0 ...
SCK    _____________/‾‾‾‾‾‾‾‾‾‾‾‾‾\______
MOSI   X== bit n =====================X== n+1
MISO   used in ph3, from miso_q captured at the start of ph3
```

- At `ph == 1` the code sets `sck <= 1` (high in phases 2–3).
- At `ph == 3` it sets `sck <= 0`, shifts out the next MOSI bit, and, once
  past the command bits (`bit_idx >= tx_bits`), shifts `miso_q` into
  `rx_sr`. Every 8th received bit completes a byte: for READ it pulses
  `fifo_wr` with `fifo_din`; for JEDEC it shifts into `jedec_id`.
- `miso_q` is an IOB register clocked every cycle; the value used was
  captured 30 ns after the SCK falling edge, which covers the STARTUPE2
  delay plus the flash clock-to-output time.

**5.4 Throughput.** A block is 32 command bits + 2048 data bits = 2080 bits
× 4 clocks = 8320 clocks, plus about 12 clocks of overhead (`S_CSLOW` 2,
`S_END` 1, `S_GAP` 8, `S_IDLE` 1). That is ≈ 83.3 µs per 256 bytes ≈
3.07 MB/s.

**5.5 Abort.** `abort_xfer = is_read && !stream_en`. A READ in progress
stops at once and goes to `S_GAP`. `fifo_wr` is only pulsed on a complete
byte, so no partial byte is written. The JEDEC read is never aborted.

**MicroBlaze mapping:** this module plus the FIFO replaces
`mb_svf_getbyte` reading from DDR. Instead of a CPU load per byte, a
hardware master streams bytes ahead of the consumer.

**Self-check**

- *Q: Why 8 dummy SCK cycles before the JEDEC ID?*
  A: STARTUPE2 swallows the first three `USRCCLKO` edges after
  configuration; the dummies use them up with CS high.
- *Q: How does pass 2 restart reading at 0x400000 after pass 1 read
  everything?*
  A: `top_ctrl` drops `stream_en` during setup. That clears `running` (and
  aborts any READ). When `stream_en` rises again, `S_IDLE` reloads
  `addr <= start_addr`.

---

### Step 6: Buffer stage — the byte FIFO

**Goal:** see how the bursty producer (flash) is decoupled from the steady
consumer (decoder), and why it can never overflow.

**Read:** `rtl/byte_fifo.sv`.

- **First-word fall-through (FWFT):** `dout` is valid whenever `empty` is
  0, and `rd_en` pops it. The decoder can therefore *look at* the current
  byte without popping it. Step 8 depends on this.
- **Two implementations:** `USE_XPM = 1` uses `xpm_fifo_sync` in block RAM
  (synthesis). `USE_XPM = 0` uses an inferred memory (Icarus simulation).
  In the XPM branch, `empty` also covers `rd_rst_busy`, and `rd_en` is
  gated so it never pops while empty or in reset.
- **`room` (credit flag):** registered, 1 when at least `ROOM` bytes are
  free (`count <= DEPTH - ROOM`). With `DEPTH = 4096` and `ROOM = 320`, the
  reader only starts a 256-byte READ when 320 bytes are free. The extra 64
  bytes absorb the one-cycle lag of `room` and the fact that the XPM write
  count may include the FWFT output stage. Only one block is in flight at a
  time, so writes never hit a full FIFO and SCK never needs to stop
  mid-byte.
- **Reset:** `rst || fifo_rst`. `top_ctrl` holds `fifo_rst` during idle and
  for the first 16 setup cycles of each pass, which flushes stale bytes.
- **Empty is harmless:** if the FIFO runs dry, the decoder just stops
  offering items and TCK stays high. JTAG is static, so a pause is fine.

**Self-check**

- *Q: What would go wrong with a standard (non-FWFT) FIFO?*
  A: Data would appear one cycle after `rd_en`, so the decoder could not
  peek at the byte holding the current TDI bit; it would need an extra
  register stage and its control would be more complex.

---

### Step 7: Decode stage, part 1 — header, CRC, opcode and arguments

**Goal:** understand how bytes become an opcode plus its arguments, and
how the header is validated.

**Read:** `rtl/crc32.sv`, then `rtl/jbin_decoder.sv` from the top to the
`D_EXEC` state.

**7.1 How the decoder is written.** It has two halves. Learn to read them
separately:

- **Combinational part** (`always_comb` blocks and `assign`s, under
  "Combinational part"): decides *this cycle* whether a FIFO byte is
  wanted (`want_pay`), available (`byte_ok`), popped (`consume`,
  `fifo_rd`), and what work item is offered to the engine (`item_v`,
  `e_tms`, `e_tdi`, …).
- **Sequential part** (`always_ff`): the state register, counters and
  stored fields.

Two SystemVerilog idioms matter:

- `fail_pass(code)` and `finish_pass(code, info)` are *tasks called inside
  `always_ff`*. They just perform non-blocking assignments; think of them as
  macros.
- **Last assignment wins.** Inside one `always_ff`, a later non-blocking
  assignment to the same signal overrides an earlier one. The decoder uses
  this on purpose: the `case` sets a default next state, then a nested
  `case`/`if` may override it, and at the very end the abort block and the
  watchdog block override everything.

**7.2 CRC.** `crc32` processes one byte per cycle (reflected polynomial
0xEDB88320, init 0xFFFFFFFF, final XOR), identical to `zlib.crc32`. Its
input is always `fifo_dout`. Control:

- `crc_init` is 1 in `D_IDLE` and in `D_HCHK` (restart for the payload).
- `crc_en` is 1 for every popped payload byte (`consume`), and in `D_HDR`
  only for header bytes 0..27 (`hdr_idx < 28`).

**7.3 States `D_IDLE` → `D_HDR` → `D_HCHK`.**

- `D_IDLE`: on `start`, clear the per-pass registers, latch `dry`
  (into `dry_q`), go to `D_HDR`.
- `D_HDR`: pop 32 bytes, shifting each into the top of a 256-bit register
  (`hdr <= {fifo_dout, hdr[255:8]}`). After 32 bytes byte 0 sits in
  `hdr[7:0]`, so the little-endian fields are simple slices
  (`hdr_magic = hdr[31:0]`, `hdr_ttck = hdr[191:128]`, …).
- `D_HCHK`: check magic, version, flags, reserved, header CRC and payload
  length. On failure `finish_pass(ST_HEADER, 0)`: the pass ends with no
  JTAG activity at all. On success latch `payload_len`, `payload_crc`,
  `total_tck`, set `hdr_valid` (enables the LED progress bar) and go to
  `D_OP`.

**7.4 States `D_OP` → `D_ARG` → `D_EXEC`.**

- `D_OP`: pop one opcode byte, set `arg_len` (TMS 1, SHIFT 5, RUNCLK 4,
  WAIT_US 4, SET_DIV 2, TRST 1). `END` is accepted only if it is the last
  payload byte (`byte_cnt + 1 == payload_len`; `byte_cnt` has not yet
  counted the END byte). Unknown opcode or misplaced END → `ST_OPCODE`.
  No bytes left (`!pay_left`) → `ST_OVERRUN`.
- `D_ARG`: pop `arg_len` bytes into `arg` little-endian
  (`arg[8*arg_idx +: 8] <= fifo_dout`). Running out of payload →
  `ST_OVERRUN`.
- `D_EXEC`: one cycle to check arguments and choose the execution state.
  It resets the bit index `bi`, sets `last_tms <= arg[32]` (SHIFT flag
  bit 0), and by default goes to `D_SYNC`:
  - TMS: `bn = n`; `n == 0` → `ST_ARG`; else `D_TMS`.
  - SHIFT: `bn = n`; `n == 0` or flags bits 7..2 non-zero → `ST_ARG`;
    compare flag (`arg[33]`) → `D_GRP`; else `D_SHIFT`.
  - RUNCLK: `n != 0` → `D_RUN`; `n == 0` stays at `D_SYNC`.
  - WAIT_US: `n != 0` and not a dry pass → `D_WAITI`; otherwise `D_SYNC`.
  - SET_DIV: `d < 2` → `ST_ARG`; else `div_file <= d`.
  - TRST: nothing.

`byte_cnt` counts popped payload bytes; `pay_left = (byte_cnt != payload_len)`
stops the decoder from ever reading past the payload.

**Self-check**

- *Q: Why is `crc_init` asserted in `D_HCHK`?*
  A: The same CRC unit is reused. In `D_HCHK` the header CRC has just been
  compared, so the unit is restarted for the payload CRC.
- *Q: Which payload bytes are covered by the payload CRC?*
  A: All of them, including the final END byte, because every popped
  payload byte (`consume`) enables the CRC.

---

### Step 8: Decode stage, part 2 — expanding opcodes into work items

**Goal:** understand the core trick that turns a 30-million-bit SHIFT into
30 million engine clocks with no stalls. This is the hardware version of
libxsvf calling `pulse_tck` in a loop.

**Read:** in `rtl/jbin_decoder.sv`, the `always_comb` blocks for `item_v`
and `consume`, the `assign`s for `e_valid`/`xfer`, and the states `D_TMS`,
`D_SHIFT`, `D_RUN`, `D_GRP`, `D_GBITS`, `D_WAITI`.

**8.1 The work item interface (decoder → engine).**

| Signal | Meaning |
|--------|---------|
| `e_valid` / `e_ready` | handshake, transfer when both are 1 |
| `e_wait` | 0: one TCK cycle; 1: wait `e_us` microseconds |
| `e_tms`, `e_tdi` | pin values for this clock |
| `e_hold` | 1: keep TDI (`tdi = -1` in libxsvf) |
| `e_chk`, `e_exp` | compare TDO of this clock against `e_exp` |
| `e_cancel` | end a running wait (abort) |
| `e_idle`, `e_err`, `e_err_tck` | engine status back to the decoder |

**8.2 Dry vs play.** These three lines implement pass 1 and pass 2 with the
same logic:

```systemverilog
assign e_valid = item_v && !dry_q;            // engine sees nothing in a dry pass
assign xfer    = item_v && (dry_q || e_ready); // dry: accepted at once
```

In a dry pass every item is "accepted" immediately, so the decoder runs
through the whole stream at FIFO speed, doing all checks, while the engine
and pins stay quiet. `tck_issued` counts accepted clock items
(`xfer && !e_wait`) in both passes.

**8.3 What each state offers:**

| State | `item_v` | TMS | TDI | hold | check |
|-------|----------|-----|-----|------|-------|
| `D_TMS` | `byte_ok` | `fifo_dout[bi[2:0]]` | – | 1 | 0 |
| `D_SHIFT` | `byte_ok` | `last_tms && last_bit` | `fifo_dout[bi[2:0]]` | 0 | 0 |
| `D_GBITS` | `!abort_q` | `last_tms && last_bit` | `g_tdi[bi[2:0]]` | 0 | `g_msk[bi]`, exp = `g_msk & g_tdo` |
| `D_RUN` | `!abort_q` | 0 | – | 1 | 0 |
| `D_WAITI` | `!abort_q` | – | – | – | wait item, `e_us = arg[31:0]` |
| `D_RESET` | 1 | 1 | – | 1 | 0 |

`bi` is the bit index inside the opcode, `bn` the bit count, and
`last_bit = (bi == bn - 1)`. On every `xfer`, `bi` increments; on the last
bit the state goes to `D_SYNC`.

**8.4 The peek path (`D_TMS`, `D_SHIFT`).** The decoder does not copy data
bytes into a register. It selects bit `bi[2:0]` straight from `fifo_dout`
(valid thanks to FWFT). The byte is popped together with the transfer of
its last bit:

```systemverilog
D_TMS, D_SHIFT: consume = xfer && ((bi[2:0] == 3'd7) || last_bit);
```

So when the engine asks for the next bit, the next byte is already on the
FIFO output. There is no bubble between bytes, even at 25 MHz TCK. If the
FIFO is empty, `byte_ok` is 0, no item is offered, and TCK simply waits
high.

**8.5 Compare shifts (`D_GRP` → `D_GBITS`).** Each group of 8 bits needs
three bytes, so the decoder loads `g_tdi`, `g_tdo`, `g_msk` in three cycles
(`D_GRP`), then offers up to 8 bits from those registers (`D_GBITS`), and
returns to `D_GRP` after bit 7 of a group if bits remain. This costs three
clocks per 8 bits, which is irrelevant because only a few dozen bits are
compared in the reference SVF.

**8.6 Opcode boundary (`D_SYNC`).** After every opcode the decoder waits
until the engine is idle (`dry_q || e_idle`), including its TDO compare
pipeline. Only then does it look at the sticky mismatch flag and the abort
request (step 11). If all is fine it goes back to `D_OP`.

**MicroBlaze mapping:** one `D_SHIFT` of `n` bits is the hardware version of
libxsvf's inner loop that calls `pulse_tck(tms, tdi, -1, ...)` `n` times.
The software took several microseconds per call; the hardware takes
exactly `2 × half` system clocks per bit.

**Self-check**

- *Q: In a 10-bit TDI-only SHIFT, when are the two data bytes popped?*
  A: Byte 0 with the transfer of bit 7 (`bi[2:0] == 7`); byte 1 with the
  transfer of bit 9 (`last_bit`).
- *Q: Why is TMS for a SHIFT `last_tms && last_bit`?*
  A: TMS stays 0 to remain in Shift-DR/IR and is 1 only on the last bit if
  the compiler asked to leave to Exit1 (flag bit 0).
- *Q: In a dry pass, why does `D_WAITI` never run?*
  A: `D_EXEC` only enters `D_WAITI` when `!dry_q`; a 100 ms wait would only
  slow down the check pass.

---

### Step 9: Execute stage — the JTAG pin engine

**Goal:** understand exact TCK timing, the handshake, and how TDO is
compared. This replaces `mb_svf_pulse_tck` and `svf_read_tdo`.

**Read:** `rtl/jtag_engine.sv`.

**9.1 States:** `E_IDLE`, `E_LOW`, `E_HIGH`, `E_WAIT`. TCK idles high.

**9.2 Accepting an item.** `item_ready = (state == E_IDLE) || last_high`,
where `last_high` is the last cycle of the high phase. On `take`
(`item_valid && item_ready`) for a clock item, at the same clock edge:
`tck_q <= 0`, `tms_q <= item_tms`, `tdi_q <= item_tdi` unless `item_hold`,
`cur_chk`/`cur_exp` latched, `half_q <= half`, `cnt <= half - 1`,
`tck_count++`, state `E_LOW`.

Because an item can be taken in the last high cycle, back-to-back items give
a continuous TCK. Note the last-assignment-wins idiom again: in `E_HIGH`
with `cnt == 0` the `case` sets `state <= E_IDLE`, but the later
`if (take)` block overrides it with `E_LOW`.

**9.3 Timing for `half = 2` (25 MHz)** (c0 is the cycle in which the item is
taken):

```text
cycle       c0    c1    c2    c3    c4    c5 ...
state       IDLE  LOW   LOW   HIGH  HIGH  LOW (next item taken in c4)
TCK         1     0     0     1     1     0
TMS/TDI     old   new   new   new   new   next
                              ^ target samples TMS/TDI on the rising edge
                                          ^ end of c4: IOB register samples TDO
```

TCK is low for `half` cycles and high for `half` cycles: one TCK costs
exactly `2 × half` system clocks, so TCK = 100 MHz / (2 × half). The target
samples TMS/TDI on the rising edge, `half × 10 ns` after they changed.

**9.4 TDO compare.** The target launches TDO after the falling edge; the
engine samples it as late as possible, at the clock edge that ends the TCK
cycle (the edge that also starts the next falling edge). That gives the
cable and the target the full TCK period for the round trip.

- `tdo_q` (IOB) samples `tdo_i` every clock; `tdo_s` is one more flip-flop.
- At the `last_high` cycle the engine pushes `{cur_chk, cur_exp,
  tck_count - 1}` into a `TDO_LAG = 2` entry pipeline (`pend_v`,
  `pend_exp`, `pend_tck`). After two clocks this entry meets `tdo_s`, which
  holds the TDO sampled at the end of that same TCK cycle.
- If `pend_v[TDO_LAG-1]` and `tdo_s != pend_exp[...]` and no error yet:
  `err <= 1`, `err_tck <= pend_tck[...]`. The first mismatch is sticky and
  its TCK index is 0-based within pass 2.
- `idle = (state == E_IDLE) && !pend_any`. "Idle" means the last clock's
  compare has completed, which is why the decoder can trust `err` once it
  sees `idle`.

**9.5 Waits.** A wait item (`item_wait = 1`) loads `us_left = item_us` and
enters `E_WAIT`. A prescaler `us_pre` counts `CLK_PER_US = 100` clocks per
microsecond and decrements `us_left`, ending when it reaches 0.
`cancel_wait` (abort) ends it early. TCK is not touched, so it stays high.
This implements SVF `RUNTEST ... SEC`, e.g. the 100 ms wait after
JPROGRAM.

**9.6 Clear.** `clear` (driven by `top_ctrl` as `eng_clear = state != T_RUN`)
puts the engine in its reset state: TCK = 1, TMS = 1, TDI = 0, counters and
`err` cleared.

**Differences from the software, worth remembering:**

- The software stopped at the first mismatching clock. The hardware
  finishes the current opcode (the mismatch is sticky), then resets the
  TAP, then reports.
- The software's `first_mismatch_clock` was taken after incrementing
  `clock_count`, i.e. 1-based. The hardware's `err_tck` is 0-based and
  counts from the start of pass 2.

**Self-check**

- *Q: With `half = 5`, how long is a TCK period and what frequency is it?*
  A: 10 system clocks = 100 ns = 10 MHz.
- *Q: Why must `idle` include `!pend_any`?*
  A: The compare result for the last clock appears two cycles after the
  state returns to idle. Without it, the decoder could check `err` too
  early and miss a mismatch on the last bit of an opcode.

---

### Step 10: TCK frequency selection

**Goal:** see how the switch setting and the SVF `FREQUENCY` combine.

**Read:** `rtl/tck_rate_selector.sv` and its wiring in `top.sv`.

| SW[2:0] | `div_sw` (half) | TCK |
|--------:|----------------:|-----|
| 0 | 5 | 10 MHz |
| 1 | 50 | 1 MHz |
| 2 | 10 | 5 MHz |
| 3 | 4 | 12.5 MHz |
| 4 | 3 | 16.7 MHz |
| 5 | 2 | 25 MHz |
| 6 | 500 | 100 kHz |
| 7 | 5000 | 10 kHz |

```systemverilog
half <= (override_en || div_sw > div_file) ? div_sw : div_file;
```

- Without SW15 the larger half period wins, so the board never clocks
  faster than the SVF asked for (`div_file`, from `SET_DIV`; default 5).
- With SW15 the switches alone decide.
- `svf2jbin` converts `FREQUENCY f` to `d = ceil(100 MHz / (2 f))`,
  clamped, so the generated TCK never exceeds the request.
- `half` is registered; the engine latches it into `half_q` at every
  `take`. `SET_DIV` is executed at an opcode boundary (`D_EXEC` →
  `D_SYNC` waits for idle), so the new rate applies cleanly from the next
  clock.

---

### Step 11: Error handling, abort and the watchdog

**Goal:** understand every way a pass can end, and what is reported.

**Read:** in `rtl/jbin_decoder.sv`: `fail_pass`, `finish_pass`, and the
states `D_SYNC`, `D_FIN`, `D_DRAIN`, `D_RESET`, `D_RDRAIN`, plus the two
override blocks at the end of the `always_ff`.

**11.1 Two exit helpers.**

- `finish_pass(code, info)`: set `status`, `err_info`, pulse `done`, clear
  `busy`, go to `D_IDLE`.
- `fail_pass(code)`: remember `pend <= code`, then
  - in a dry pass go to `D_DRAIN`: read the rest of the payload so the CRC
    can be checked. If the CRC is wrong, report `ST_CRC` instead, because a
    corrupt stream explains the format error. Otherwise report `pend` with
    `byte_cnt`.
  - in a play pass go to `D_RESET`: clock five TMS = 1 cycles (Test-Logic-
    Reset from any TAP state), then `D_RDRAIN` waits for the engine to be
    idle and reports `pend`.

**11.2 Normal end (`D_FIN`).** Reached by a correct END. After the engine is
idle (or at once in a dry pass): a TDO error goes to `D_RESET` with
`ST_TDO`; else wrong CRC → `ST_CRC`; else `tck_issued != total_tck` →
`ST_TCK`; else `ST_OK`. The CRC and TCK-count errors here end the pass
directly without `D_RESET`. In practice they are caught in pass 1; and the
compiled stream already ends with the walk to Test-Logic-Reset that
`libxsvf_play()` does.

**11.3 Opcode boundary checks (`D_SYNC`).** When `dry_q || e_idle`:

- abort requested: dry → `finish_pass(ST_ABORT, tck_issued)`; play →
  `D_RESET` with `pend = ST_ABORT`;
- else play and `e_err`: `D_RESET` with `pend = ST_TDO`;
- else back to `D_OP`.

**11.4 Abort.** `abort_q` is set when `abort && busy`. It immediately:

- makes `want_pay = 0` and `item_v = 0` in the issuing states, so no byte
  is popped and no new item is offered;
- drives `e_cancel`, ending a running wait in the engine;
- via the override block at the end, forces any of `D_HDR … D_DRAIN` to
  `D_SYNC`, which then takes the abort path above.

**11.5 Watchdog.** `wd` counts consecutive cycles in which the decoder
wants a byte and the FIFO is empty (`waiting_byte`). At `TIMEOUT_CYCLES`
(0.5 s): in a dry pass or in `D_HDR` → `finish_pass(ST_TIMEOUT, byte_cnt)`;
during play → `fail_pass(ST_TIMEOUT)` (TAP reset first). Waiting for the
engine (for example a 100 ms `WAIT_US`, or a slow TCK) does not count,
because the decoder is not waiting for a byte then.

**11.6 Status codes and the `info` word** (printed in hex on the UART):

| Code | UART text | Meaning | `info` |
|-----:|-----------|---------|--------|
| 1 | `OK` | pass completed | `tck_issued` (= `total_tck`) |
| 2 | `ERR TDO` | TDO mismatch | `e_err_tck`, 0-based TCK index in pass 2 |
| 3 | `ERR HDR` | bad header | 0 |
| 4 | `ERR OPC` | unknown opcode or misplaced END | `byte_cnt` |
| 5 | `ERR OVR` | opcode runs past `payload_len` | `byte_cnt` |
| 6 | `ERR CRC` | payload CRC wrong | the computed CRC |
| 7 | `ERR TCK` | clock count ≠ header `total_tck` | `tck_issued` |
| 8 | `ABORT` | BTNU | `tck_issued` (during play this includes the 5 reset clocks); 0 if aborted during setup |
| 9 | `ERR ARG` | bad argument (TMS n = 0, SHIFT n = 0 or bad flags, SET_DIV < 2) | `byte_cnt` |
| 10 | `ERR FLID` | flash JEDEC ID rejected | JEDEC ID |
| 11 | `ERR TOUT` | flash stream stalled 0.5 s | `byte_cnt` |
| 12 | `FLASH OK` | JEDEC ID accepted (after power-up) | JEDEC ID |

Codes 10 and 12 come from `top_ctrl`, not from the decoder.

For codes 4, 5 and 9, `byte_cnt` means different things in the two passes.
In pass 1 the error is reported after `D_DRAIN` has read the rest of the
payload, so `byte_cnt` equals `payload_len`. In pass 2 (only possible with
SW14) it is the payload position where the error was found.

**Self-check**

- *Q: A TDO mismatch occurs on bit 3 of a 32-bit compare SHIFT during
  play. What happens next?*
  A: The engine sets `err` and records the TCK index. The decoder finishes
  the remaining 28 bits of that SHIFT, enters `D_SYNC`, waits for idle,
  sees `e_err`, clocks five TMS = 1 cycles in `D_RESET`, waits in
  `D_RDRAIN`, then reports `ERR TDO` with that index.
- *Q: In a dry pass the decoder finds an unknown opcode but the payload is
  also corrupt. What is reported?*
  A: `ERR CRC`, because `D_DRAIN` reads the rest of the payload and the CRC
  check takes priority.

---

### Step 12: System control — two passes, LEDs and UART

**Goal:** understand the sequencing that the MicroBlaze `main` menu loop
used to do.

**Read:** `rtl/top_ctrl.sv`, then `rtl/uart_tx_status.sv`.

**12.1 State machine:**

```text
T_ID ──id_done && id_ok──> T_READY        (UART "FLASH OK")
T_ID ──id_done && !id_ok──> T_IDERR       (UART "ERR FLID", stays here)
T_READY ──start, or auto_start once──> T_SETUP
T_SETUP ──64 cycles──> T_RUN              (decoder started)
T_SETUP ──abort──> T_READY                (UART "ABORT")
T_RUN ──done, pass 1 OK, no abort──> T_SETUP (pass 2)
T_RUN ──done otherwise──> T_READY         (UART result)
```

- `T_READY`: `stream_en = 0`, `fifo_rst = 1`, `jtag_oe = 0`, `abort_req`
  cleared. On `start` (BTNC rise) or `auto_start && !auto_done`: set
  `pass2 <= skip_check` (SW14 skips pass 1) and go to setup.
- `T_SETUP` (64 cycles): `stream_en = 0` (reader stops and will restart at
  0x400000), `fifo_rst` for the first 16 cycles (FIFO flushed),
  `jtag_oe <= pass2` (pins driven only for pass 2; the engine is held in
  `clear`, so the pins show TCK = 1, TMS = 1, TDI = 0). In the last cycle:
  `stream_en <= 1`, `dec_dry <= !pass2`, pulse `dec_start`.
- `T_RUN`: BTNU sets `abort_req`, which is `dec_abort`. On `dec_done`: if
  pass 1 ended OK and there was no abort, go back to `T_SETUP` with
  `pass2 = 1`. Otherwise store the result, send the UART line, drop
  `stream_en` and `jtag_oe`, and return to `T_READY`.
- `fin_status`: if an abort arrives just as pass 1 completes OK, it is
  still reported as `ABORT`.

**12.2 Why two passes.** Pass 1 (dry) reads and checks the *whole* stream
(header, every opcode and argument, END position, payload CRC, total TCK
count) with the pins in high impedance. Only a fully verified stream is
played on the target. The software had no equivalent; libxsvf found
syntax problems only while already driving the target.

**12.3 LEDs.** LD0 ready, LD1 busy, LD2 OK, LD3 TDO mismatch, LD4 stream
error (header, opcode, overrun, CRC, TCK count, argument, timeout), LD5 flash
ID error, LD6 aborted, LD7 pass 1 running. LD15..8: while busy a progress
bar (`LED[8+k]` on when `tck_issued × 8 ≥ total_tck × (k+1)`); after a
result all on for OK, the JEDEC manufacturer byte for a flash ID error,
otherwise the status code.

**12.4 UART.** `uart_tx_status` prints one fixed-format line per event with
no CPU:

```text
JTAG <8-char text> 0x<16 lowercase hex digits of info>\r\n    (34 characters)
```

A combinational block picks character `idx` (prefix, text from
`code_text`, `" 0x"`, hex nibbles MSB first, CR, LF); a baud counter of
`CLK_PER_BIT = 868` clocks sends start bit, 8 data bits LSB first, stop
bit. `send` is ignored while a line is being transmitted (≈ 3 ms per line).

**MicroBlaze mapping:** the `p` command and its printed result become
BTNC + two passes + LEDs + one UART line. `xil_printf` becomes a hardwired
string generator.

---

### Step 13: Trace one complete run

**Goal:** tie all modules together in time. Do this on paper.

1. **Power-up.** The FPGA configures itself from flash address 0x0
   (programmer bitstream). `STARTUPE2` raises `EOS`.
2. **Reset.** `reset_gen` holds `rst` for 31 cycles. All FSMs start:
   `top_ctrl` in `T_ID`, reader in `S_EOS`, decoder in `D_IDLE`, engine
   idle with JTAG pins in high impedance (`jtag_oe = 0`).
3. **Flash check.** Reader: 8 dummy SCK cycles → gap → `0x9F` → 3 ID
   bytes → `id_done`, `id_ok`. `top_ctrl` prints `JTAG FLASH OK 0x…` and
   enters `T_READY` (LD0 on).
4. **Start.** BTNC (debounced, 10 ms) → `T_SETUP`, `pass2 = 0` (unless
   SW14). FIFO flushed, reader stopped.
5. **Pass 1 (dry).** `stream_en` rises → reader loads 0x400000 and streams
   256-byte blocks whenever `fifo_room`. Decoder: header → check → opcodes
   at FIFO speed, items accepted instantly, CRC and `tck_issued`
   accumulate → END → `D_FIN` → `ST_OK`. About 1.25 s for the reference
   stream, limited by the flash (3.07 MB/s). LD7 and the progress bar are
   on.
6. **Setup for pass 2.** `top_ctrl` returns to `T_SETUP` with `pass2 = 1`:
   `jtag_oe = 1` (pins now drive TCK = 1, TMS = 1, TDI = 0), FIFO flushed,
   reader restarted.
7. **Pass 2 (play).** Same decoding, but items go to the engine. TMS walks,
   the IDCODE compare, JPROGRAM, the 100 ms `WAIT_US`, the 30,606,304-bit
   configuration `SHIFT` (peek path, one TCK per `2 × half` clocks), JSTART,
   the status compare, and the final walk to Test-Logic-Reset.
8. **Result.** `D_FIN` checks `e_err`, CRC and TCK count → `ST_OK`.
   `top_ctrl` prints `JTAG OK` with `info = tck_issued`, lights LD2 and
   LD15..8, drops `jtag_oe` (pins high impedance again) and returns to
   `T_READY`. The architecture report gives 30,716,788 clocks for the
   reference stream, which prints as `0x0000000001d4b374`.

At the default 10 MHz this takes ≈ 1.25 s + 3.07 s + 0.1 s ≈ 4.4 s
(≈ 3.2 s with SW14), compared with ≈ 30–40 s for the MicroBlaze `p` mode.

---

### Step 14: Confirm your understanding

**Goal:** watch the signals you have studied and try to break things.

1. **Run the testbenches** (Icarus Verilog 12 or newer, from
   `hw/jtag_programmer_fpga_only`):

   ```text
   python sim/run_icarus.py                 # all tests
   python sim/run_icarus.py tb_jtag_engine  # one test
   ```

   In Vivado use `sim/run_sim.tcl` (xsim with the XPM FIFO).

2. **Study them in this order**, matching the steps above:

   | Testbench | Covers | Steps |
   |-----------|--------|-------|
   | `sim/tb_spi_flash_reader.sv` (+ `sim/models/spi_flash_model.sv`) | flash timing, throughput, JEDEC | 5, 6 |
   | `sim/tb_jtag_engine.sv` | TCK timing, waits, TDO round trip, mismatch index | 9 |
   | `sim/tb_jbin_decoder.sv` | 17 valid and invalid streams × 2 passes against the model, random back-pressure | 7, 8, 11 |
   | `sim/tb_top.sv` (+ `sim/models/tap_model.sv`) | complete system with a 7-series TAP model: programming, TDO fault, CRC/header faults, skip check, abort, flash ID error, FIFO stalls, auto start, frequency switches | 12, 13 |

3. **Use the reference model.** `tools/jbin_model.py input.jbin --trace
   out.trc --events out.txt` writes the per-TCK trace. Given an
   `ERR TDO` index, find that line in the trace to see which opcode and
   bit failed.

4. **Exercises** (in simulation):
   - Convert `sim/svf/idcode.svf` with
     `python tools/svf2jbin.py sim/svf/idcode.svf idcode.jbin --report`,
     decode its bytes by hand with the rules from step 3, then follow
     `state`, `bi`, `fifo_rd`, `e_valid`, `e_ready` and `tck_o` in a
     waveform of `tb_jbin_decoder` or `tb_top`.
   - Set SW[2:0] = 5 (`half = 2`) and confirm 4 system clocks per TCK.
   - Flip one payload byte and confirm that pass 1 reports `ERR CRC` and
     the JTAG pins never leave high impedance.
   - In the TDO fault scenario of `tb_top`, confirm `ERR TDO`, the five
     TMS = 1 clocks that follow, and the reported TCK index.

---

## Quick reference: where to look for…

| Question | Place |
|----------|-------|
| How a byte is fetched from flash | `spi_flash_reader.sv`, `S_XFER` |
| Why the FIFO cannot overflow | `byte_fifo.sv`, `room`; `spi_flash_reader.sv`, `S_IDLE` |
| How the header is checked | `jbin_decoder.sv`, `D_HCHK` |
| How one SHIFT becomes many clocks | `jbin_decoder.sv`, `item_v`/`consume` blocks and `D_SHIFT` |
| How TCK is generated | `jtag_engine.sv`, `E_LOW`/`E_HIGH` and `take` |
| How TDO is compared | `jtag_engine.sv`, compare stage (`pend_*`) |
| What happens on an error | `jbin_decoder.sv`, `fail_pass`, `D_RESET`, `D_DRAIN` |
| Pass 1 / pass 2 sequencing | `top_ctrl.sv`, `T_SETUP`/`T_RUN` |
| TCK frequency | `tck_rate_selector.sv` |
