#!/usr/bin/env python3
"""Generate the t_random vector files from tools/gpio_reg_model.py.

    python sim/vectors/gen_vectors.py          # writes random_seed1..5.txt

One operation per line, all numbers in hex:

    W <addr> <data> <strb> <gpio>   write; <gpio> is gpio_io_o after it
    R <addr> <data>                 read; <data> is the expected RDATA
    I <value>                       drive gpio2_io_i
    T <cycles>                      wait clock cycles

The testbench resets the DUT before t_random, so the model starts from reset.
The first operations drive the inputs to 0 because their value after earlier
tests is unknown. Every I is followed by T 3, so a later DATA2 read sees a
settled input (GPIO-SYN-002).

The files are committed so the Linux server does not need Python.
"""

import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "tools"))

from gpio_reg_model import (ADDR_WIDTH, DATA, DATA2, TRI, TRI2,  # noqa: E402
                            AxiGpioJtag)

SEEDS = (1, 2, 3, 4, 5)
OPS_PER_FILE = 2000
MAPPED = (DATA, TRI, DATA2, TRI2)


def random_addr(rng):
    r = rng.random()
    if r < 0.70:
        return rng.choice(MAPPED)
    if r < 0.85:
        return rng.choice(MAPPED) + rng.randrange(1, 4)
    return rng.randrange(0x10, 1 << ADDR_WIDTH)


def generate(seed, count):
    rng = random.Random(seed)
    model = AxiGpioJtag()
    lines = ["I 0", "T 3"]
    model.set_inputs(0)
    model.tick(3)
    for _ in range(count):
        r = rng.random()
        addr = random_addr(rng)
        if r < 0.45:
            data = rng.randrange(1 << 32)
            strb = 0xF if rng.random() < 0.5 else rng.randrange(16)
            model.write(addr, data, strb)
            lines.append("W %03x %08x %x %x" % (addr, data, strb, model.gpio_out))
        elif r < 0.85:
            value, _ = model.read(addr)
            lines.append("R %03x %08x" % (addr, value))
        elif r < 0.95:
            pins = rng.randrange(16)
            model.set_inputs(pins)
            model.tick(3)
            lines.append("I %x" % pins)
            lines.append("T 3")
        else:
            cycles = rng.randrange(1, 6)
            model.tick(cycles)
            lines.append("T %x" % cycles)
    return lines


def main():
    for seed in SEEDS:
        path = os.path.join(HERE, "random_seed%d.txt" % seed)
        lines = generate(seed, OPS_PER_FILE)
        with open(path, "w", encoding="ascii", newline="\n") as f:
            f.write("\n".join(lines) + "\n")
        print("wrote %s (%d lines)" % (path, len(lines)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
