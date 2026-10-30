#!/usr/bin/env python3
"""Reference player for JBIN v1 streams.

It applies the same checks as the RTL decoder (rtl/jbin_decoder.sv) and
expands the stream into a per-TCK trace. Each trace byte describes one TCK
cycle:

    bit 0  TMS
    bit 1  TDI
    bit 2  expected TDO (0 when not checked)
    bit 3  TDO is checked

Non-clock events (WAIT_US, SET_DIV, TRST) are listed separately together
with the TCK index at which they occur.

Usage: jbin_model.py input.jbin [--trace out.trc] [--events out.txt]
"""

import argparse
import sys

from jbin_common import (DIV_MIN, HEADER_SIZE, OP_END, OP_RUNCLK, OP_SET_DIV,
                         OP_SHIFT, OP_TMS, OP_TRST, OP_WAIT_US, SHIFT_COMPARE,
                         SHIFT_LAST_TMS, JbinError, crc32, parse_header)

_BIT_TO_TDI = bytes.maketrans(b"01", b"\x00\x02")


def _bits_lsb_first(data, n):
    """Return a bytes object with one '0'/'1' character per bit, LSB first."""
    value = int.from_bytes(data, "little")
    return format(value, "b").zfill(n)[::-1][:n].encode()


class Model:
    def __init__(self, data):
        self.header = parse_header(data)
        end = HEADER_SIZE + self.header["payload_len"]
        if len(data) < end:
            raise JbinError("file is shorter than header payload_len")
        self.payload = data[HEADER_SIZE:end]
        if crc32(self.payload) != self.header["payload_crc"]:
            raise JbinError("payload CRC mismatch")
        self.pos = 0
        self.trace = bytearray()
        self.events = []
        self.tdi = 0

    def _take(self, n):
        if self.pos + n > len(self.payload):
            raise JbinError("opcode at payload offset %d runs past the payload"
                            % self.pos)
        chunk = self.payload[self.pos:self.pos + n]
        self.pos += n
        return chunk

    def _u(self, n):
        return int.from_bytes(self._take(n), "little")

    def run(self):
        while True:
            op_pos = self.pos
            op = self._u(1)
            if op == OP_TMS:
                n = self._u(1)
                if n == 0:
                    raise JbinError("TMS with zero bits at %d" % op_pos)
                bits = self._take((n + 7) // 8)
                held = self.tdi << 1
                for i in range(n):
                    tms = (bits[i >> 3] >> (i & 7)) & 1
                    self.trace.append(held | tms)
            elif op == OP_SHIFT:
                n = self._u(4)
                flags = self._u(1)
                if n == 0 or flags & ~(SHIFT_LAST_TMS | SHIFT_COMPARE):
                    raise JbinError("bad SHIFT arguments at %d" % op_pos)
                nbytes = (n + 7) // 8
                if flags & SHIFT_COMPARE:
                    data = self._take(nbytes * 3)
                    tdi, tdo, mask = data[0::3], data[1::3], data[2::3]
                    for i in range(n):
                        b, s = i >> 3, i & 7
                        t = (tdi[b] >> s) & 1
                        chk = (mask[b] >> s) & 1
                        exp = ((tdo[b] >> s) & 1) if chk else 0
                        self.trace.append((chk << 3) | (exp << 2) | (t << 1))
                else:
                    data = self._take(nbytes)
                    self.trace += _bits_lsb_first(data, n).translate(
                        _BIT_TO_TDI)
                if flags & SHIFT_LAST_TMS:
                    self.trace[-1] |= 1
                self.tdi = (self.trace[-1] >> 1) & 1
            elif op == OP_RUNCLK:
                n = self._u(4)
                self.trace += bytes([self.tdi << 1]) * n
            elif op == OP_WAIT_US:
                us = self._u(4)
                if us:
                    self.events.append((len(self.trace), "WAIT", us))
            elif op == OP_SET_DIV:
                div = self._u(2)
                if div < DIV_MIN:
                    raise JbinError("SET_DIV %d below minimum at %d"
                                    % (div, op_pos))
                self.events.append((len(self.trace), "DIV", div))
            elif op == OP_TRST:
                self.events.append((len(self.trace), "TRST", self._u(1)))
            elif op == OP_END:
                if self.pos != len(self.payload):
                    raise JbinError("END at %d is not the last payload byte"
                                    % op_pos)
                break
            else:
                raise JbinError("unknown opcode 0x%02x at %d" % (op, op_pos))
        if len(self.trace) != self.header["total_tck"]:
            raise JbinError("header total_tck %d but stream has %d clocks"
                            % (self.header["total_tck"], len(self.trace)))
        return self


def load(path):
    with open(path, "rb") as f:
        return Model(f.read()).run()


def write_events(events, path):
    with open(path, "w", newline="\n") as f:
        for tck, kind, value in events:
            f.write("%d %s %d\n" % (tck, kind, value))


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("jbin")
    ap.add_argument("--trace", help="write the per-TCK trace to this file")
    ap.add_argument("--events", help="write non-clock events to this file")
    args = ap.parse_args(argv)
    try:
        model = load(args.jbin)
    except (JbinError, OSError) as exc:
        print("jbin_model: error: %s" % exc, file=sys.stderr)
        return 1
    if args.trace:
        with open(args.trace, "wb") as f:
            f.write(model.trace)
    if args.events:
        write_events(model.events, args.events)
    checks = sum(model.trace.count(bytes([v])) for v in range(8, 16))
    print("JBIN OK: %d TCK, %d TDO checks, %d events"
          % (len(model.trace), checks, len(model.events)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
