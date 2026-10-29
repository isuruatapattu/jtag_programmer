#!/usr/bin/env python3
"""Generate the simulation vectors used by the testbenches.

Output directory (default build/sim/vectors), all in $readmemh format:

  case_<i>.hex         JBIN bytes of test case i (flash data at 0x400000)
  case_<i>_trace.hex   expected per-TCK trace (jbin_model.py bit layout)
  case_<i>_events.hex  expected WAIT/DIV events: tck, kind (1 WAIT, 2 DIV),
                       value; three 32-bit words per event
  cases.hex            32-bit words: number of cases, then per case
                       nbytes, dry status, play status, trace length,
                       number of events, IDCODE-error flag
  cases.txt            human-readable list of the cases
  reader.hex           64 KiB of pseudo-random bytes for tb_spi_flash_reader

Status codes are those of rtl/jbin_decoder.sv.
"""

import argparse
import os
import random
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "tools"))

import jbin_model  # noqa: E402
import svf2jbin  # noqa: E402
from jbin_common import (HEADER_SIZE, OP_END, OP_RUNCLK, OP_SET_DIV,  # noqa: E402
                         OP_SHIFT, OP_TMS, crc32, pack_header)

ST_OK, ST_TDO, ST_HEADER, ST_OPCODE, ST_OVERRUN = 1, 2, 3, 4, 5
ST_CRC, ST_TCK, ST_ARG, ST_TIMEOUT = 6, 7, 9, 11


def jbin(payload, total_tck, payload_crc=None):
    if payload_crc is None:
        payload_crc = crc32(payload)
    return pack_header(len(payload), payload_crc, total_tck) + payload


def with_header_field(data, offset, fmt, value, fix_crc=True):
    """Patch a header field and (optionally) recompute the header CRC."""
    head = bytearray(data[:HEADER_SIZE])
    struct.pack_into(fmt, head, offset, value)
    if fix_crc:
        struct.pack_into("<I", head, 28, crc32(bytes(head[:28])))
    return bytes(head) + data[HEADER_SIZE:]


def runclk(n):
    return bytes([OP_RUNCLK]) + struct.pack("<I", n)


def build_cases():
    svf = {n: svf2jbin.convert(os.path.join(HERE, "svf", n + ".svf"))[0]
           for n in ("idcode", "short_prog", "features")}
    idc = svf["idcode"]
    cases = []

    def add(name, data, dry, play, idcode_err=False):
        cases.append((name, data, dry, play, idcode_err))

    add("idcode", idc, ST_OK, ST_OK)
    add("short_prog", svf["short_prog"], ST_OK, ST_OK)
    add("features", svf["features"], ST_OK, ST_OK)
    # The TAP model returns a wrong IDCODE: TDO mismatch during play only.
    add("idcode_tdo_error", idc, ST_OK, ST_TDO, idcode_err=True)

    add("bad_magic", with_header_field(idc, 0, "<4s", b"JBIM"),
        ST_HEADER, ST_HEADER)
    add("bad_header_crc", with_header_field(idc, 28, "<I", 0x12345678,
                                            fix_crc=False),
        ST_HEADER, ST_HEADER)
    add("bad_version", with_header_field(idc, 4, "<H", 2),
        ST_HEADER, ST_HEADER)

    payload = runclk(3) + bytes([OP_SHIFT]) + struct.pack("<IB", 16, 0) + \
        b"\x12\x34" + bytes([OP_END])
    good_crc = crc32(payload)
    bad = bytearray(payload)
    bad[11] ^= 0x01
    add("bad_payload_crc", jbin(bytes(bad), 19, good_crc), ST_CRC, ST_CRC)

    add("bad_opcode", jbin(runclk(2) + b"\x07" + bytes([OP_END]), 2),
        ST_OPCODE, ST_OPCODE)
    add("bad_arg_tms0", jbin(bytes([OP_TMS, 0, OP_END]), 0),
        ST_ARG, ST_ARG)
    add("bad_arg_div", jbin(bytes([OP_SET_DIV, 1, 0, OP_END]), 0),
        ST_ARG, ST_ARG)
    add("bad_arg_flags", jbin(bytes([OP_SHIFT]) + struct.pack("<IB", 8, 4) +
                              b"\x00" + bytes([OP_END]), 8),
        ST_ARG, ST_ARG)
    add("overrun_no_end", jbin(runclk(5), 5), ST_OVERRUN, ST_OVERRUN)
    add("overrun_mid_shift", jbin(bytes([OP_SHIFT]) +
                                  struct.pack("<IB", 64, 0) + b"\xAA\x55",
                                  64),
        ST_OVERRUN, ST_OVERRUN)
    add("end_not_last", jbin(bytes([OP_END, 0x00]), 0),
        ST_OPCODE, ST_OPCODE)
    add("bad_total_tck", with_header_field(idc, 16, "<Q",
                                           jbin_model.Model(idc).run()
                                           .header["total_tck"] + 1),
        ST_TCK, ST_TCK)
    # Header claims more payload than the stream provides.
    trunc = jbin(runclk(4), 4)
    trunc = with_header_field(trunc, 8, "<I", 64)
    add("truncated", trunc, ST_TIMEOUT, ST_TIMEOUT)
    return cases


def write_hex(path, data, width=1):
    with open(path, "w", newline="\n") as f:
        if not data:
            f.write("0" * (2 * width) + "\n")
        for v in data:
            f.write("%0*x\n" % (2 * width, v))


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--out", default=os.path.join(ROOT, "build", "sim",
                                                  "vectors"))
    args = ap.parse_args(argv)
    os.makedirs(args.out, exist_ok=True)

    cases = build_cases()
    words = [len(cases)]
    with open(os.path.join(args.out, "cases.txt"), "w", newline="\n") as f:
        for i, (name, data, dry, play, idc_err) in enumerate(cases):
            trace, events = b"", []
            if dry == ST_OK:
                model = jbin_model.Model(data).run()
                trace = bytes(model.trace)
                kinds = {"WAIT": 1, "DIV": 2}
                events = [(t, kinds[k], v) for t, k, v in model.events
                          if k in kinds]
            else:
                try:
                    jbin_model.Model(data).run()
                except jbin_model.JbinError:
                    pass
                else:
                    sys.exit("case %s: jbin_model accepts it" % name)
            write_hex(os.path.join(args.out, "case_%d.hex" % i), data)
            write_hex(os.path.join(args.out, "case_%d_trace.hex" % i), trace)
            write_hex(os.path.join(args.out, "case_%d_events.hex" % i),
                      [w for e in events for w in e], width=4)
            words += [len(data), dry, play, len(trace), len(events),
                      int(idc_err)]
            f.write("%2d %-18s bytes=%-6d dry=%-2d play=%-2d tck=%d\n"
                    % (i, name, len(data), dry, play, len(trace)))
    write_hex(os.path.join(args.out, "cases.hex"), words, width=4)

    rng = random.Random(1234)
    write_hex(os.path.join(args.out, "reader.hex"),
              bytes(rng.getrandbits(8) for _ in range(65536)))
    print("wrote %d cases to %s" % (len(cases), args.out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
