#!/usr/bin/env python3
"""Reference model of axi_gpio_jtag, from doc/axi_gpio_jtag_spec.md.

The model works at the register level: one call is one completed AXI4-Lite
transaction. The only clocked state it keeps is the 2-stage input
synchronizer, advanced by tick(). AXI handshake timing is not modelled; the
testbench assertions cover it.

    python tools/gpio_reg_model.py            # run every check
    python tools/gpio_reg_model.py --list     # list checks and spec IDs
    python tools/gpio_reg_model.py --seed 7   # change the random seed

Each check is tagged with the spec IDs it covers. The run fails if those tags
do not match the "Model check" column of doc/traceability.md.
"""

import argparse
import os
import random
import re
import sys

OKAY = 0

ADDR_WIDTH = 9
DATA_MASK = 0xFFFFFFFF
STATE_MASK = 0xF

DATA = 0x000
TRI = 0x004
DATA2 = 0x008
TRI2 = 0x00C
MAPPED = (DATA, TRI, DATA2, TRI2)

RESET_DATA = 0x0
RESET_TRI = 0x0
RESET_TRI2 = 0xF

SYNC_STAGES = 2
SYNC_STABLE_CYCLES = 3


class AxiGpioJtag:
    """Register-level model of axi_gpio_jtag."""

    def __init__(self):
        # GPIO-RST-006: the synchronizer has no reset. Simulation starts it
        # at X; the model starts it at 0 and no check depends on that value.
        self._pins = 0
        self._sync = [0] * SYNC_STAGES
        self.reset()

    def reset(self):
        """GPIO-RST-003: reset values. The synchronizer keeps its contents."""
        self._data = RESET_DATA
        self._tri = RESET_TRI
        self._tri2 = RESET_TRI2

    @staticmethod
    def _offset(addr):
        if not 0 <= addr < (1 << ADDR_WIDTH):
            raise ValueError("address 0x%x does not fit in %d bits"
                             % (addr, ADDR_WIDTH))
        return addr & ~0x3

    def write(self, addr, data, wstrb=0xF):
        """One AXI write. Returns BRESP."""
        if not 0 <= data <= DATA_MASK:
            raise ValueError("data 0x%x is wider than 32 bits" % data)
        if not 0 <= wstrb <= 0xF:
            raise ValueError("wstrb 0x%x is wider than 4 bits" % wstrb)
        offset = self._offset(addr)
        if wstrb & 0x1:
            value = data & STATE_MASK
            if offset == DATA:
                self._data = value
            elif offset == TRI:
                self._tri = value
            elif offset == TRI2:
                self._tri2 = value
        return OKAY

    def read(self, addr):
        """One AXI read. Returns (RDATA, RRESP)."""
        offset = self._offset(addr)
        if offset == DATA:
            value = self._data
        elif offset == TRI:
            value = self._tri
        elif offset == DATA2:
            value = self._sync[-1]
        elif offset == TRI2:
            value = self._tri2
        else:
            value = 0
        return value, OKAY

    def set_inputs(self, value):
        """Drive gpio2_io_i. Takes effect in the synchronizer on tick()."""
        if not 0 <= value <= STATE_MASK:
            raise ValueError("input 0x%x is wider than 4 bits" % value)
        self._pins = value

    def tick(self, cycles=1):
        """Advance the synchronizer by rising edges of s_axi_aclk."""
        for _ in range(cycles):
            self._sync = [self._pins] + self._sync[:-1]

    @property
    def gpio_out(self):
        """gpio_io_o, which always equals the DATA register (GPIO-REG-003)."""
        return self._data


# ---------------------------------------------------------------------------
# Checks
# ---------------------------------------------------------------------------

CHECKS = []


def check(*spec_ids):
    def register(func):
        CHECKS.append((func.__name__, spec_ids, func))
        return func
    return register


def expect(actual, expected, what):
    if actual != expected:
        raise AssertionError("%s: got 0x%x, expected 0x%x"
                             % (what, actual, expected))


def read_value(model, addr):
    value, resp = model.read(addr)
    expect(resp, OKAY, "RRESP at 0x%03x" % addr)
    return value


def write_ok(model, addr, data, wstrb=0xF):
    expect(model.write(addr, data, wstrb), OKAY, "BRESP at 0x%03x" % addr)


def settle_inputs(model, value):
    model.set_inputs(value)
    model.tick(SYNC_STABLE_CYCLES)


def snapshot(model):
    return {addr: read_value(model, addr) for addr in MAPPED}, model.gpio_out


@check("GPIO-ADR-001")
def check_addr_low_bits_ignored(model, rng):
    settle_inputs(model, 0x9)
    for base in (DATA, TRI, TRI2):
        for low in range(4):
            value = rng.randrange(16)
            write_ok(model, base + low, value)
            for low_rd in range(4):
                expect(read_value(model, base + low_rd), value,
                       "read 0x%03x after write 0x%03x"
                       % (base + low_rd, base + low))
    for low in range(4):
        expect(read_value(model, DATA2 + low), 0x9, "DATA2 + %d" % low)


@check("GPIO-ADR-002")
def check_register_map(model, rng):
    write_ok(model, DATA, 0x3)
    write_ok(model, TRI, 0x5)
    write_ok(model, TRI2, 0x6)
    settle_inputs(model, 0xA)
    expect(read_value(model, DATA), 0x3, "DATA")
    expect(read_value(model, TRI), 0x5, "TRI")
    expect(read_value(model, DATA2), 0xA, "DATA2")
    expect(read_value(model, TRI2), 0x6, "TRI2")


@check("GPIO-ADR-003")
def check_unmapped_read(model, rng):
    write_ok(model, DATA, 0xF)
    write_ok(model, TRI, 0xF)
    settle_inputs(model, 0xF)
    for offset in range(0x010, 1 << ADDR_WIDTH, 4):
        expect(read_value(model, offset), 0, "unmapped 0x%03x" % offset)


@check("GPIO-ADR-004")
def check_unmapped_write(model, rng):
    write_ok(model, DATA, 0x5)
    write_ok(model, TRI, 0x6)
    write_ok(model, TRI2, 0x7)
    before = snapshot(model)
    for offset in range(0x010, 1 << ADDR_WIDTH, 4):
        write_ok(model, offset, DATA_MASK)
        if snapshot(model) != before:
            raise AssertionError("write to unmapped 0x%03x changed state"
                                 % offset)


@check("GPIO-REG-001", "GPIO-REG-003")
def check_data_write(model, rng):
    for value in range(16):
        write_ok(model, DATA, value)
        expect(model.gpio_out, value, "gpio_io_o after DATA = 0x%x" % value)


@check("GPIO-REG-002")
def check_data_read(model, rng):
    for _ in range(64):
        value = rng.randrange(1 << 32)
        write_ok(model, DATA, value)
        settle_inputs(model, rng.randrange(16))
        expect(read_value(model, DATA), value & STATE_MASK,
               "DATA read is not the output register")


@check("GPIO-REG-004")
def check_tri_storage(model, rng):
    write_ok(model, DATA, 0xA)
    for value in range(16):
        write_ok(model, TRI, value)
        expect(read_value(model, TRI), value, "TRI read-back")
        expect(model.gpio_out, 0xA, "gpio_io_o after TRI = 0x%x" % value)


@check("GPIO-REG-005")
def check_data2_read(model, rng):
    for value in range(16):
        settle_inputs(model, value)
        expect(read_value(model, DATA2), value, "DATA2")


@check("GPIO-REG-006")
def check_data2_write_ignored(model, rng):
    settle_inputs(model, 0x6)
    write_ok(model, DATA, 0x3)
    before = snapshot(model)
    for value in (0x0, 0xF, DATA_MASK, 0x9):
        write_ok(model, DATA2, value)
        if snapshot(model) != before:
            raise AssertionError("write 0x%x to DATA2 changed state" % value)


@check("GPIO-REG-007")
def check_tri2_storage(model, rng):
    for value in range(16):
        write_ok(model, TRI2, value)
        expect(read_value(model, TRI2), value, "TRI2 read-back")
        pins = rng.randrange(16)
        settle_inputs(model, pins)
        expect(read_value(model, DATA2), pins,
               "DATA2 with TRI2 = 0x%x" % value)


@check("GPIO-REG-008")
def check_upper_bits_zero(model, rng):
    settle_inputs(model, 0xF)
    for _ in range(64):
        value = rng.randrange(1 << 32) | 0xFFFFFFF0
        for addr in (DATA, TRI, TRI2):
            write_ok(model, addr, value)
        for addr in MAPPED:
            if read_value(model, addr) & ~STATE_MASK:
                raise AssertionError("bits [31:4] set at 0x%03x" % addr)


@check("GPIO-STB-001")
def check_wstrb0_clear(model, rng):
    write_ok(model, DATA, 0x5)
    write_ok(model, TRI, 0x6)
    write_ok(model, TRI2, 0x7)
    before = snapshot(model)
    for wstrb in range(0, 16, 2):
        for addr in (DATA, TRI, DATA2, TRI2):
            write_ok(model, addr, rng.randrange(1 << 32), wstrb)
            if snapshot(model) != before:
                raise AssertionError("wstrb 0x%x changed 0x%03x"
                                     % (wstrb, addr))


@check("GPIO-STB-002")
def check_wstrb_upper_ignored(model, rng):
    for wstrb in range(1, 16, 2):
        for addr in (DATA, TRI, TRI2):
            value = rng.randrange(1 << 32)
            write_ok(model, addr, value, wstrb)
            expect(read_value(model, addr), value & STATE_MASK,
                   "0x%03x with wstrb 0x%x" % (addr, wstrb))


@check("GPIO-AXI-015")
def check_read_after_write(model, rng):
    shadow = {DATA: RESET_DATA, TRI: RESET_TRI, TRI2: RESET_TRI2}
    for _ in range(2000):
        addr = rng.choice((DATA, TRI, TRI2))
        if rng.random() < 0.5:
            value = rng.randrange(1 << 32)
            wstrb = rng.randrange(16)
            write_ok(model, addr, value, wstrb)
            if wstrb & 0x1:
                shadow[addr] = value & STATE_MASK
        else:
            expect(read_value(model, addr), shadow[addr],
                   "read 0x%03x after completed writes" % addr)


@check("GPIO-SYN-001", "GPIO-SYN-002")
def check_sync_latency(model, rng):
    model.set_inputs(0x0)
    model.tick(SYNC_STABLE_CYCLES)
    for _ in range(200):
        old = read_value(model, DATA2)
        new = rng.randrange(16)
        model.set_inputs(new)
        for edge in range(1, SYNC_STABLE_CYCLES + 1):
            model.tick()
            got = read_value(model, DATA2)
            if edge < SYNC_STAGES:
                expect(got, old, "DATA2 %d edge after change" % edge)
            else:
                expect(got, new, "DATA2 %d edges after change" % edge)


@check("GPIO-RST-001", "GPIO-RST-003")
def check_reset_values(model, rng):
    for _ in range(16):
        write_ok(model, DATA, rng.randrange(1 << 32))
        write_ok(model, TRI, rng.randrange(1 << 32))
        write_ok(model, TRI2, rng.randrange(1 << 32))
        model.reset()
        expect(model.gpio_out, 0x0, "gpio_io_o after reset")
        expect(read_value(model, DATA), RESET_DATA, "DATA after reset")
        expect(read_value(model, TRI), RESET_TRI, "TRI after reset")
        expect(read_value(model, TRI2), RESET_TRI2, "TRI2 after reset")


@check("GPIO-SW-001")
def check_sw_configure(model, rng):
    write_ok(model, DATA, 0xF)
    write_ok(model, TRI, 0xF)
    write_ok(model, TRI2, 0x0)
    write_ok(model, TRI, 0x00000000)
    write_ok(model, TRI2, 0xFFFFFFFF)
    write_ok(model, DATA, 0x00000000)
    expect(model.gpio_out, 0x0, "gpio_io_o")
    expect(read_value(model, TRI), 0x0, "TRI")
    expect(read_value(model, TRI2), 0xF, "TRI2")
    expect(read_value(model, DATA), 0x0, "DATA")


@check("GPIO-SW-002")
def check_sw_test_outputs(model, rng):
    for value in (0x1, 0x2, 0x4, 0x8, 0xF, 0x0):
        write_ok(model, DATA, value & STATE_MASK)
        expect(model.gpio_out, value, "gpio_io_o in test pattern")


@check("GPIO-SW-003")
def check_sw_write_read_tdo(model, rng):
    for _ in range(256):
        shadow = rng.randrange(1 << 32)
        write_ok(model, DATA, shadow & STATE_MASK)
        expect(model.gpio_out, shadow & STATE_MASK, "gpio_io_o")
        pins = rng.randrange(16)
        settle_inputs(model, pins)
        value = read_value(model, DATA2)
        expect(value, pins, "DATA2")
        expect(value & 0x1, pins & 0x1, "TDO bit")


@check("GPIO-SW-004")
def check_sw_loopback(model, rng):
    def loopback_read(tck):
        write_ok(model, DATA, tck)
        settle_inputs(model, model.gpio_out & 0x1)
        return read_value(model, DATA2) & 0x1

    expect(loopback_read(0x0), 0, "TDO with TCK low")
    expect(loopback_read(0x1), 1, "TDO with TCK high")
    write_ok(model, DATA, 0x0)
    expect(model.gpio_out, 0x0, "gpio_io_o after loopback")


@check("GPIO-SW-005")
def check_sw_stream(model, rng):
    seen = []
    for i in range(10000):
        value = rng.randrange(8)
        write_ok(model, DATA, value)
        seen.append(model.gpio_out)
        expect(seen[-1], value, "gpio_io_o at write %d" % i)
        if i % 97 == 0:
            pins = rng.randrange(16)
            settle_inputs(model, pins)
            expect(read_value(model, DATA2), pins, "DATA2 at write %d" % i)
    expect(len(seen), 10000, "number of writes observed")


# ---------------------------------------------------------------------------
# Traceability cross-check and runner
# ---------------------------------------------------------------------------

TRACE = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(
    __file__))), "doc", "traceability.md")


def trace_model_checks(path):
    """Map spec ID -> model check name from the traceability table."""
    mapping = {}
    with open(path, encoding="utf-8") as f:
        for line in f:
            if not line.startswith("| GPIO-"):
                continue
            cells = [c.strip() for c in line.strip().strip("|").split("|")]
            name = cells[2].strip("`")
            if name != "-":
                mapping[cells[0]] = name
    return mapping


def model_checks():
    return {spec_id: name for name, ids, _ in CHECKS for spec_id in ids}


def cross_check_trace(path):
    if not os.path.exists(path):
        return ["traceability file not found: %s" % path]
    expected = trace_model_checks(path)
    actual = model_checks()
    errors = []
    for spec_id in sorted(set(expected) | set(actual)):
        want = expected.get(spec_id)
        have = actual.get(spec_id)
        if want != have:
            errors.append("%s: traceability says %s, model has %s"
                          % (spec_id, want, have))
    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--list", action="store_true")
    args = parser.parse_args()

    if args.list:
        for name, ids, _ in CHECKS:
            print("%-28s %s" % (name, " ".join(ids)))
        return 0

    failures = 0
    for name, ids, func in CHECKS:
        try:
            func(AxiGpioJtag(), random.Random("%d:%s" % (args.seed, name)))
        except AssertionError as exc:
            failures += 1
            print("FAIL %-28s %s: %s" % (name, " ".join(ids), exc))
        else:
            print("PASS %-28s %s" % (name, " ".join(ids)))

    errors = cross_check_trace(TRACE)
    for err in errors:
        print("TRACE %s" % err)

    covered = len(model_checks())
    print("%d checks, %d spec IDs, %d failed, %d traceability errors"
          % (len(CHECKS), covered, failures, len(errors)))
    return 1 if failures or errors else 0


if __name__ == "__main__":
    sys.exit(main())
