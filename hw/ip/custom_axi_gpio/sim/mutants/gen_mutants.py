#!/usr/bin/env python3
"""Write broken copies of the RTL for the mutant runs.

    python sim/mutants/gen_mutants.py

Each mutant changes exactly one line of one RTL file and is written to
sim/mutants/<name>/<file>. manifest.txt lists "name|file|description".
"bash sim/run.sh <tool> mutants" compiles the testbench against each mutant
and expects at least one test or assertion to fail.

Run this again whenever the RTL changes. It stops with an error if a pattern
is no longer found exactly once.
"""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
RTL = os.path.join(HERE, "..", "..", "rtl")

MUTANTS = [
    ("m01_rdata_follows", "axi_lite_slave.v",
     "if (ar_hs) rdata <= reg_rd_data;",
     "rdata <= reg_rd_data;",
     "rdata follows the register file while R is stalled (GPIO-AXI-011)"),
    ("m02_live_awaddr", "axi_lite_slave.v",
     "assign reg_wr_addr = aw_seen ? awaddr_q : awaddr;",
     "assign reg_wr_addr = awaddr;",
     "write uses the live AWADDR instead of the captured one (GPIO-AXI-002)"),
    ("m03_wstrb_ignored", "gpio_jtag_regs.v",
     "wire wr_ok = wr_en & wr_strb[0];",
     "wire wr_ok = wr_en;",
     "wstrb[0] = 0 still writes (GPIO-STB-001)"),
    ("m04_unmapped_alias", "gpio_jtag_regs.v",
     "default:   rd_data = 32'd0;",
     "default:   rd_data = {28'd0, data_q};",
     "unmapped offsets read DATA (GPIO-ADR-003)"),
    ("m05_tri2_reset", "gpio_jtag_regs.v",
     "tri2_q <= 4'hF;",
     "tri2_q <= 4'h0;",
     "TRI2 resets to 0x0 (GPIO-RST-003)"),
    ("m06_sync_one_stage", "gpio_jtag_regs.v",
     "IDX_DATA2: rd_data = {28'd0, sync_q2};",
     "IDX_DATA2: rd_data = {28'd0, sync_q1};",
     "DATA2 reads the first synchronizer stage (GPIO-SYN-001)"),
    ("m07_bvalid_pulse", "axi_lite_slave.v",
     "wire bvalid_n  = commit | (bvalid & ~bready);",
     "wire bvalid_n  = commit;",
     "bvalid drops before bready (GPIO-AXI-004)"),
    ("m08_same_cycle_write_lost", "axi_lite_slave.v",
     "assign reg_wr_en   = commit;",
     "assign reg_wr_en   = commit & ~(aw_hs & w_hs);",
     "write lost when AW and W arrive in the same cycle (GPIO-AXI-001)"),
]


def main():
    manifest = ["# name|file|description"]
    for name, fname, old, new, desc in MUTANTS:
        with open(os.path.join(RTL, fname), encoding="ascii") as f:
            text = f.read()
        count = text.count(old)
        if count != 1:
            print("ERROR %s: pattern found %d times in %s: %s"
                  % (name, count, fname, old))
            return 1
        out_dir = os.path.join(HERE, name)
        os.makedirs(out_dir, exist_ok=True)
        with open(os.path.join(out_dir, fname), "w", encoding="ascii",
                  newline="\n") as f:
            f.write(text.replace(old, new))
        manifest.append("%s|%s|%s" % (name, fname, desc))
        print("wrote %s/%s" % (name, fname))
    with open(os.path.join(HERE, "manifest.txt"), "w", encoding="ascii",
              newline="\n") as f:
        f.write("\n".join(manifest) + "\n")
    print("wrote manifest.txt (%d mutants)" % len(MUTANTS))
    return 0


if __name__ == "__main__":
    sys.exit(main())
