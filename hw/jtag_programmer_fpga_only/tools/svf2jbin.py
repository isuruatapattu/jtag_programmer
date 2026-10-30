#!/usr/bin/env python3
"""Convert an SVF file into a JBIN v1 command stream.

The SVF semantics follow libxsvf (sw/nexys_a7/app_mb_svf_player/external/
libxsvf/svf.c and tap.c) bit for bit, because that is the player that is
known to program the target correctly:

- TAP walks use the same transition choices as libxsvf_tap_walk().
- HIR/HDR/TIR/TDR and the scan register contents are sticky per register
  exactly as in bitdata_parse(): a register keeps its TDI/MASK/SMASK data
  while its length does not change, and TDO must be given on every scan
  that should be checked.
- Unmasked (SMASK = 0) and absent TDI bits keep the previous TDI pin value.
- RUNTEST walks to the run state, clocks, waits, then walks to the end state.
- The stream ends with the walk to Test-Logic-Reset done by libxsvf_play().

Usage: svf2jbin.py input.svf output.jbin [--report]
"""

import argparse
import re
import sys

from jbin_common import (HEADER_SIZE, MAX_PAYLOAD, OP_END,
                         OP_RUNCLK, OP_SET_DIV, OP_SHIFT, OP_TMS, OP_TRST,
                         OP_WAIT_US, SHIFT_COMPARE, SHIFT_LAST_TMS, JbinError,
                         crc32, freq_to_div, pack_header)

(INIT, RESET, IDLE, DRSELECT, DRCAPTURE, DRSHIFT, DREXIT1, DRPAUSE, DREXIT2,
 DRUPDATE, IRSELECT, IRCAPTURE, IRSHIFT, IREXIT1, IRPAUSE, IREXIT2,
 IRUPDATE) = range(17)

STATE_NAMES = {
    "RESET": RESET, "IDLE": IDLE, "DRSELECT": DRSELECT,
    "DRCAPTURE": DRCAPTURE, "DRSHIFT": DRSHIFT, "DREXIT1": DREXIT1,
    "DRPAUSE": DRPAUSE, "DREXIT2": DREXIT2, "DRUPDATE": DRUPDATE,
    "IRSELECT": IRSELECT, "IRCAPTURE": IRCAPTURE, "IRSHIFT": IRSHIFT,
    "IREXIT1": IREXIT1, "IRPAUSE": IRPAUSE, "IREXIT2": IREXIT2,
    "IRUPDATE": IRUPDATE,
}

INT32_MAX = 0x7FFFFFFF


class SvfError(Exception):
    pass


# ---------------------------------------------------------------------------
# Tokenizer
# ---------------------------------------------------------------------------

_PAREN_RE = re.compile(r"\(([^()]*)\)")
_WS_RE = re.compile(r"\s+")


def _normalize_command(text):
    text = _PAREN_RE.sub(lambda m: " (" + _WS_RE.sub("", m.group(1)) + ") ",
                         text)
    return text.upper().split()


def read_commands(path, chunk_size=1 << 20):
    """Yield (line_number, tokens) for every ';'-terminated SVF command.

    The file is read in chunks; only complete lines are processed so that
    '!' and '//' comments are always seen whole.
    """
    parts = []
    has_text = False
    line_no = 0
    cmd_line = 1
    tail = ""
    with open(path, "r", encoding="latin-1", newline="") as f:
        while True:
            chunk = f.read(chunk_size)
            eof = not chunk
            data = tail + chunk
            if eof:
                lines = data.splitlines(True) if data else []
                tail = ""
            else:
                lines = data.splitlines(True)
                tail = ""
                if lines and not lines[-1].endswith(("\n", "\r")):
                    tail = lines.pop()
            for line in lines:
                line_no += 1
                cut = len(line)
                bang = line.find("!")
                if bang >= 0:
                    cut = bang
                slash = line.find("//", 0, cut)
                if slash >= 0:
                    cut = slash
                body = line[:cut]
                while True:
                    semi = body.find(";")
                    piece = body if semi < 0 else body[:semi]
                    if piece.strip():
                        if not has_text:
                            cmd_line = line_no
                            has_text = True
                        parts.append(piece)
                    parts.append(" ")
                    if semi < 0:
                        break
                    yield cmd_line, _normalize_command("".join(parts))
                    parts = []
                    has_text = False
                    body = body[semi + 1:]
            if eof:
                break
    if has_text:
        raise SvfError("unexpected end of file inside a command")


# ---------------------------------------------------------------------------
# TAP walker (port of libxsvf_tap_walk)
# ---------------------------------------------------------------------------

def tap_walk_bits(state, target):
    bits = []
    i = 0
    while target != state:
        if state == INIT:
            bits += [1] * 6
            state = RESET
        elif state == RESET:
            bits.append(0); state = IDLE
        elif state == IDLE:
            bits.append(1); state = DRSELECT
        elif state == DRSELECT:
            if target >= IRSELECT or target == RESET:
                bits.append(1); state = IRSELECT
            else:
                bits.append(0); state = DRCAPTURE
        elif state == DRCAPTURE:
            if target == DRSHIFT:
                bits.append(0); state = DRSHIFT
            else:
                bits.append(1); state = DREXIT1
        elif state == DRSHIFT:
            bits.append(1); state = DREXIT1
        elif state == DREXIT1:
            if target == DRPAUSE:
                bits.append(0); state = DRPAUSE
            else:
                bits.append(1); state = DRUPDATE
        elif state == DRPAUSE:
            bits.append(1); state = DREXIT2
        elif state == DREXIT2:
            if target == DRSHIFT:
                bits.append(0); state = DRSHIFT
            else:
                bits.append(1); state = DRUPDATE
        elif state == DRUPDATE:
            if target == IDLE:
                bits.append(0); state = IDLE
            else:
                bits.append(1); state = DRSELECT
        elif state == IRSELECT:
            if target == RESET:
                bits.append(1); state = RESET
            else:
                bits.append(0); state = IRCAPTURE
        elif state == IRCAPTURE:
            if target == IRSHIFT:
                bits.append(0); state = IRSHIFT
            else:
                bits.append(1); state = IREXIT1
        elif state == IRSHIFT:
            bits.append(1); state = IREXIT1
        elif state == IREXIT1:
            if target == IRPAUSE:
                bits.append(0); state = IRPAUSE
            else:
                bits.append(1); state = IRUPDATE
        elif state == IRPAUSE:
            bits.append(1); state = IREXIT2
        elif state == IREXIT2:
            if target == IRSHIFT:
                bits.append(0); state = IRSHIFT
            else:
                bits.append(1); state = IRUPDATE
        elif state == IRUPDATE:
            if target == IDLE:
                bits.append(0); state = IDLE
            else:
                bits.append(1); state = DRSELECT
        else:
            raise SvfError("illegal TAP state %d" % state)
        if i > 10:
            raise SvfError("loop in TAP walker")
        i += 1
    return bits, state


# ---------------------------------------------------------------------------
# Scan registers (port of struct bitdata_s / bitdata_parse)
# ---------------------------------------------------------------------------

class BitData:
    FIELDS = {"TDI": "tdi", "TDO": "tdo", "SMASK": "tdi_mask",
              "MASK": "tdo_mask", "RMASK": "ret_mask"}

    def __init__(self, name):
        self.name = name
        self.len = 0
        self.alloced_len = 0
        self.tdi = None
        self.tdi_mask = None
        self.tdo = None
        self.tdo_mask = None
        self.ret_mask = None
        self.has_tdo = False

    def parse(self, tokens):
        if not tokens or not re.fullmatch(r"\d*", tokens[0]):
            length_tok = ""
        else:
            length_tok = tokens[0]
            tokens = tokens[1:]
        self.len = int(length_tok) if length_tok else 0
        self.has_tdo = False
        if self.len != self.alloced_len:
            self.tdi = self.tdi_mask = self.tdo = None
            self.tdo_mask = self.ret_mask = None
            self.alloced_len = self.len
        nbytes = (self.len + 7) // 8
        while tokens:
            key = tokens[0]
            if key not in self.FIELDS or len(tokens) < 2:
                raise SvfError("%s: bad field %r" % (self.name, key))
            m = re.fullmatch(r"\(([0-9A-F]*)\)", tokens[1])
            if not m:
                raise SvfError("%s: bad hex data for %s" % (self.name, key))
            digits = m.group(1)
            if len(digits) > nbytes * 2:
                raise SvfError("%s: %s has more hex digits than %d bits"
                               % (self.name, key, self.len))
            value = int(digits, 16) if digits else 0
            if self.len:
                value &= (1 << self.len) - 1
            else:
                value = 0
            setattr(self, self.FIELDS[key], value)
            if key == "TDO":
                self.has_tdo = True
            tokens = tokens[2:]


# ---------------------------------------------------------------------------
# JBIN emitter
# ---------------------------------------------------------------------------

class Emitter:
    def __init__(self):
        self.payload = bytearray()
        self.pending_tms = []
        self.total_tck = 0
        self.tdi_pin = 0
        self.stats = {"tms_bits": 0, "shift_bits": 0, "runclk": 0,
                      "wait_us": 0, "compare_bits": 0}

    def tms(self, bits):
        self.pending_tms.extend(bits)

    def _flush_tms(self):
        bits = self.pending_tms
        self.pending_tms = []
        for start in range(0, len(bits), 255):
            part = bits[start:start + 255]
            packed = bytearray((len(part) + 7) // 8)
            for i, b in enumerate(part):
                if b:
                    packed[i >> 3] |= 1 << (i & 7)
            self.payload.append(OP_TMS)
            self.payload.append(len(part))
            self.payload += packed
            self.total_tck += len(part)
            self.stats["tms_bits"] += len(part)

    def shift(self, n, tdi_bits, last_tms, compare, tdo_bits, mask_bits):
        self._flush_tms()
        nbytes = (n + 7) // 8
        flags = (SHIFT_LAST_TMS if last_tms else 0) | \
                (SHIFT_COMPARE if compare else 0)
        self.payload.append(OP_SHIFT)
        self.payload += n.to_bytes(4, "little")
        self.payload.append(flags)
        tdi_b = tdi_bits.to_bytes(nbytes, "little")
        if compare:
            data = bytearray(nbytes * 3)
            data[0::3] = tdi_b
            data[1::3] = (tdo_bits & mask_bits).to_bytes(nbytes, "little")
            data[2::3] = mask_bits.to_bytes(nbytes, "little")
            self.payload += data
            self.stats["compare_bits"] += bin(mask_bits).count("1")
        else:
            self.payload += tdi_b
        self.total_tck += n
        self.stats["shift_bits"] += n
        self.tdi_pin = (tdi_bits >> (n - 1)) & 1

    def runclk(self, n):
        self._flush_tms()
        if n > 0xFFFFFFFF:
            raise SvfError("RUNTEST clock count too large")
        if n:
            self.payload.append(OP_RUNCLK)
            self.payload += n.to_bytes(4, "little")
            self.total_tck += n
            self.stats["runclk"] += n

    def wait_us(self, us):
        self._flush_tms()
        if us:
            self.payload.append(OP_WAIT_US)
            self.payload += us.to_bytes(4, "little")
            self.stats["wait_us"] += us

    def set_div(self, div):
        self._flush_tms()
        self.payload.append(OP_SET_DIV)
        self.payload += div.to_bytes(2, "little")

    def trst(self, value):
        self._flush_tms()
        self.payload.append(OP_TRST)
        self.payload.append(value)

    def finish(self):
        self._flush_tms()
        self.payload.append(OP_END)
        if len(self.payload) > MAX_PAYLOAD:
            raise SvfError("JBIN payload of %d bytes does not fit in flash"
                           % len(self.payload))
        header = pack_header(len(self.payload), crc32(self.payload),
                             self.total_tck)
        return header + bytes(self.payload)


# ---------------------------------------------------------------------------
# SVF player (port of libxsvf_svf)
# ---------------------------------------------------------------------------

_RUNTEST_NUM_RE = re.compile(r"(\d+)(?:E(-?)(\d*))?(.*)")
_FREQ_NUM_RE = re.compile(r"(\d+)(?:\.(\d*))?(?:E([+-]?)(\d*))?(.*)")


def _c_int(value, what):
    if value > INT32_MAX:
        raise SvfError("%s overflows a 32-bit int in libxsvf" % what)
    return value


class SvfConverter:
    def __init__(self):
        self.em = Emitter()
        self.state = INIT
        self.endir = IDLE
        self.enddr = IDLE
        self.run_state = IDLE
        self.endrun = IDLE
        self.regs = {k: BitData(k) for k in
                     ("HDR", "HIR", "TDR", "TIR", "SDR", "SIR")}
        self.command_counts = {}
        self.warnings = []

    def walk(self, target):
        bits, self.state = tap_walk_bits(self.state, target)
        self.em.tms(bits)

    def play(self, bd, estate):
        n = bd.len
        if n == 0:
            return
        last_tms = self.state != estate
        if last_tms:
            self.state += 1
        full = (1 << n) - 1
        pin = self.em.tdi_pin
        if bd.tdi is None:
            tdi_bits = full if pin else 0
        elif bd.tdi_mask is None or bd.tdi_mask == full:
            tdi_bits = bd.tdi
        else:
            tdi_bits = 0
            for k in range(n):
                if (bd.tdi_mask >> k) & 1:
                    pin = (bd.tdi >> k) & 1
                tdi_bits |= pin << k
        compare = False
        tdo_bits = mask_bits = 0
        if bd.has_tdo:
            mask_bits = full if bd.tdo_mask is None else bd.tdo_mask
            tdo_bits = bd.tdo
            compare = mask_bits != 0
        if bd.ret_mask:
            self.warnings.append("%s RMASK ignored (no readback)" % bd.name)
        self.em.shift(n, tdi_bits, last_tms, compare, tdo_bits, mask_bits)

    def scan(self, kind, tokens):
        if kind == "SDR":
            head, body, tail = (self.regs["HDR"], self.regs["SDR"],
                                self.regs["TDR"])
            shift_state, end_state = DRSHIFT, self.enddr
        else:
            head, body, tail = (self.regs["HIR"], self.regs["SIR"],
                                self.regs["TIR"])
            shift_state, end_state = IRSHIFT, self.endir
        body.parse(tokens)
        self.walk(shift_state)
        self.play(head, shift_state if body.len + tail.len > 0 else end_state)
        self.play(body, shift_state if tail.len > 0 else end_state)
        self.play(tail, end_state)
        self.walk(end_state)

    def runtest(self, tokens):
        tck_count = -1
        min_time = -1
        i = 0
        while i < len(tokens):
            tok = tokens[i]
            got_endstate = False
            if tok == "MAXIMUM":
                i += 1
                tok = tokens[i] if i < len(tokens) else ""
                got_maximum = True
            else:
                got_maximum = False
            if tok == "ENDSTATE":
                i += 1
                tok = tokens[i] if i < len(tokens) else ""
                got_endstate = True
            if tok in STATE_NAMES:
                if got_endstate:
                    self.endrun = STATE_NAMES[tok]
                else:
                    self.run_state = STATE_NAMES[tok]
                i += 1
                continue
            m = _RUNTEST_NUM_RE.fullmatch(tok)
            if not m:
                raise SvfError("RUNTEST syntax error at %r" % tok)
            number = _c_int(int(m.group(1)), "RUNTEST number")
            if m.group(2) is not None or m.group(3) is not None:
                exp = int(m.group(3)) if m.group(3) else 0
                if m.group(2) == "-":
                    exp = -exp
                number_e6, exp_e6 = number, exp + 6
                while exp < 0:
                    number //= 10
                    exp += 1
                while exp > 0:
                    number = _c_int(number * 10, "RUNTEST number")
                    exp -= 1
                while exp_e6 < 0:
                    number_e6 //= 10
                    exp_e6 += 1
                while exp_e6 > 0:
                    number_e6 *= 10
                    exp_e6 -= 1
            else:
                number_e6 = number * 1000000
            unit = m.group(4)
            i += 1
            if not unit:
                unit = tokens[i] if i < len(tokens) else ""
                i += 1
            if unit == "SEC":
                number_e6 = _c_int(number_e6, "RUNTEST time in us")
                if got_maximum:
                    self.warnings.append("RUNTEST MAXIMUM time ignored")
                else:
                    min_time = number_e6
            elif unit == "TCK":
                tck_count = number
            elif unit == "SCK":
                pass
            else:
                raise SvfError("RUNTEST syntax error at unit %r" % unit)
        self.walk(self.run_state)
        if min_time >= 0 or tck_count >= 0:
            self.em.runclk(tck_count if tck_count >= 0 else 0)
            self.em.wait_us(min_time if min_time >= 0 else 0)
        self.walk(self.endrun)

    def frequency(self, tokens):
        if not tokens:
            raise SvfError("FREQUENCY without a value")
        m = _FREQ_NUM_RE.fullmatch(tokens[0])
        if not m:
            raise SvfError("FREQUENCY syntax error")
        number = int(m.group(1) + (m.group(2) or ""))
        frac = len(m.group(2) or "")
        exp = int(m.group(4)) if m.group(4) else 0
        if m.group(3) == "-":
            exp = -exp
        exp -= frac
        freq = number * 10 ** exp if exp >= 0 else number // 10 ** (-exp)
        rest = tokens[1:]
        if not m.group(5):
            rest = rest[1:]
        if rest:
            raise SvfError("FREQUENCY: unexpected %r" % rest[0])
        self.em.set_div(freq_to_div(freq))

    def command(self, tokens):
        if not tokens:
            return
        cmd, args = tokens[0], tokens[1:]
        self.command_counts[cmd] = self.command_counts.get(cmd, 0) + 1
        if cmd in ("ENDIR", "ENDDR"):
            if len(args) != 1 or args[0] not in STATE_NAMES:
                raise SvfError("%s needs one TAP state" % cmd)
            if cmd == "ENDIR":
                self.endir = STATE_NAMES[args[0]]
            else:
                self.enddr = STATE_NAMES[args[0]]
        elif cmd == "FREQUENCY":
            self.frequency(args)
        elif cmd in ("HDR", "HIR", "TDR", "TIR"):
            self.regs[cmd].parse(args)
        elif cmd in ("PIO", "PIOMAP"):
            raise SvfError("unsupported command %s" % cmd)
        elif cmd == "RUNTEST":
            self.runtest(args)
        elif cmd in ("SDR", "SIR"):
            self.scan(cmd, args)
        elif cmd == "STATE":
            for tok in args:
                if tok not in STATE_NAMES:
                    raise SvfError("STATE: bad state %r" % tok)
                self.walk(STATE_NAMES[tok])
        elif cmd == "TRST":
            values = {"OFF": 0, "ON": 1, "Z": 2, "ABSENT": 3}
            if len(args) != 1 or args[0] not in values:
                raise SvfError("TRST syntax error")
            self.em.trst(values[args[0]])
        else:
            raise SvfError("unknown command %s" % cmd)

    def finish(self):
        self.walk(RESET)
        return self.em.finish()


def convert(svf_path):
    conv = SvfConverter()
    for line_no, tokens in read_commands(svf_path):
        try:
            conv.command(tokens)
        except (SvfError, JbinError) as exc:
            raise SvfError("line %d: %s" % (line_no, exc)) from None
    return conv.finish(), conv


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("svf")
    ap.add_argument("jbin")
    ap.add_argument("--report", action="store_true",
                    help="print a summary of the conversion")
    args = ap.parse_args(argv)
    try:
        data, conv = convert(args.svf)
    except (SvfError, JbinError, OSError) as exc:
        print("svf2jbin: error: %s" % exc, file=sys.stderr)
        return 1
    with open(args.jbin, "wb") as f:
        f.write(data)
    if args.report:
        em = conv.em
        print("output:       %s (%d bytes)" % (args.jbin, len(data)))
        print("payload:      %d bytes" % (len(data) - HEADER_SIZE))
        print("total TCK:    %d" % em.total_tck)
        print("  TMS walks:  %d" % em.stats["tms_bits"])
        print("  scan bits:  %d" % em.stats["shift_bits"])
        print("  RUNTEST:    %d" % em.stats["runclk"])
        print("TDO checks:   %d bits" % em.stats["compare_bits"])
        print("waits:        %d us" % em.stats["wait_us"])
        print("commands:     %s" % ", ".join(
            "%s=%d" % kv for kv in sorted(conv.command_counts.items())))
        for w in sorted(set(conv.warnings)):
            print("warning:      %s" % w)
    return 0


if __name__ == "__main__":
    sys.exit(main())
