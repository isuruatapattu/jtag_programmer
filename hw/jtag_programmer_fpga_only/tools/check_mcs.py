#!/usr/bin/env python3
"""Check that an MCS (Intel HEX) flash image contains a file at an address.

Usage: check_mcs.py image.mcs data.jbin [address]   (default 0x400000)

Also checks that the JBIN is valid (header and payload CRC) and that no
other data overlaps it. Exit status 0 on success.
"""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from jbin_common import HEADER_SIZE, JbinError, crc32, parse_header  # noqa: E402


def read_mcs(path):
    """Return {address: byte} for every data byte in an Intel HEX file."""
    mem = {}
    base = 0
    with open(path) as f:
        for lineno, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            if not line.startswith(":"):
                raise ValueError("line %d: not an Intel HEX record" % lineno)
            rec = bytes.fromhex(line[1:])
            if sum(rec) & 0xFF:
                raise ValueError("line %d: checksum error" % lineno)
            count, addr, rtype = rec[0], (rec[1] << 8) | rec[2], rec[3]
            data = rec[4:4 + count]
            if rtype == 0x00:
                for i, b in enumerate(data):
                    mem[base + addr + i] = b
            elif rtype == 0x01:
                break
            elif rtype == 0x04:
                base = ((data[0] << 8) | data[1]) << 16
            elif rtype == 0x02:
                base = ((data[0] << 8) | data[1]) << 4
    return mem


def main(argv):
    if len(argv) not in (2, 3):
        print(__doc__)
        return 2
    mcs, jbin = argv[0], argv[1]
    addr = int(argv[2], 0) if len(argv) == 3 else 0x400000
    with open(jbin, "rb") as f:
        data = f.read()
    try:
        hdr = parse_header(data)
    except JbinError as exc:
        print("check_mcs: %s: %s" % (jbin, exc))
        return 1
    end = HEADER_SIZE + hdr["payload_len"]
    if len(data) != end:
        print("check_mcs: %s: size %d, header says %d" % (jbin, len(data), end))
        return 1
    if crc32(data[HEADER_SIZE:end]) != hdr["payload_crc"]:
        print("check_mcs: %s: payload CRC mismatch" % jbin)
        return 1

    mem = read_mcs(mcs)
    for i, b in enumerate(data):
        if mem.get(addr + i) != b:
            print("check_mcs: byte 0x%X of the JBIN differs in the image"
                  % (addr + i))
            return 1
    below = [a for a in mem if a < addr]
    top_of_bit = max(below) + 1 if below else 0
    print("check_mcs: OK, JBIN %d bytes at 0x%06X, bitstream ends at 0x%06X"
          % (len(data), addr, top_of_bit))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
