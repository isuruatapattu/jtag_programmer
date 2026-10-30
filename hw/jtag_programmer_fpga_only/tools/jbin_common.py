"""Shared definitions for the JBIN v1 format (see doc/jbin_format.md)."""

import struct
import zlib

MAGIC = b"JBIN"
VERSION = 1
HEADER_SIZE = 32
HEADER_FMT = "<4sHHIIQII"

OP_TMS = 0x01
OP_SHIFT = 0x02
OP_RUNCLK = 0x03
OP_WAIT_US = 0x04
OP_SET_DIV = 0x05
OP_TRST = 0x06
OP_END = 0xFF

SHIFT_LAST_TMS = 0x01
SHIFT_COMPARE = 0x02

SYS_CLK_HZ = 100_000_000
DIV_MIN = 2
DIV_MAX = 0xFFFF
DIV_DEFAULT = 5

FLASH_SIZE = 16 * 1024 * 1024
FLASH_DATA_BASE = 0x0040_0000
MAX_PAYLOAD = FLASH_SIZE - FLASH_DATA_BASE - HEADER_SIZE


class JbinError(Exception):
    pass


def crc32(data, value=0):
    return zlib.crc32(data, value) & 0xFFFFFFFF


def freq_to_div(freq_hz):
    """Half period in system clocks for a requested TCK frequency.

    Rounds up so the generated TCK never exceeds the requested frequency.
    """
    if freq_hz <= 0:
        return DIV_MAX
    div = -(-SYS_CLK_HZ // (2 * int(freq_hz)))
    return max(DIV_MIN, min(DIV_MAX, div))


def pack_header(payload_len, payload_crc, total_tck):
    head = struct.pack(HEADER_FMT[:-1], MAGIC, VERSION, 0, payload_len,
                       payload_crc, total_tck, 0)
    return head + struct.pack("<I", crc32(head))


def parse_header(data):
    if len(data) < HEADER_SIZE:
        raise JbinError("file shorter than the JBIN header")
    (magic, version, flags, payload_len, payload_crc, total_tck, reserved,
     header_crc) = struct.unpack(HEADER_FMT, data[:HEADER_SIZE])
    if magic != MAGIC:
        raise JbinError("bad magic %r" % magic)
    if version != VERSION:
        raise JbinError("unsupported version %d" % version)
    if flags != 0 or reserved != 0:
        raise JbinError("reserved header fields are not zero")
    if crc32(data[:HEADER_SIZE - 4]) != header_crc:
        raise JbinError("header CRC mismatch")
    if payload_len == 0:
        raise JbinError("empty payload")
    if payload_len > MAX_PAYLOAD:
        raise JbinError("payload_len %d does not fit in flash" % payload_len)
    return {
        "payload_len": payload_len,
        "payload_crc": payload_crc,
        "total_tck": total_tck,
    }
