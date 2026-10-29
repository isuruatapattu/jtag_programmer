#!/usr/bin/env python3
"""Run the whole testbench suite with Icarus Verilog (iverilog 12 or newer).

The same testbenches run in Vivado xsim through sim/run_sim.tcl; this script
exists for machines without Vivado. Run it from anywhere:

    python sim/run_icarus.py            # all tests
    python sim/run_icarus.py tb_top     # tests whose name contains "tb_top"

The XPM FIFO is replaced by the inferred FIFO (byte_fifo USE_XPM = 0),
because Icarus has no Xilinx XPM library.
"""

import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
BUILD = os.path.join(ROOT, "build", "sim")

RTL = ["rtl/crc32.sv", "rtl/byte_fifo.sv", "rtl/spi_flash_reader.sv",
       "sim/models/flash_sck_startup_sim.sv", "rtl/jtag_engine.sv",
       "rtl/jbin_decoder.sv", "rtl/debounce.sv", "rtl/uart_tx_status.sv",
       "rtl/top_ctrl.sv", "rtl/top.sv"]
MODELS = ["sim/models/spi_flash_model.sv", "sim/models/tap_model.sv"]

# (name, top module, extra sources, parameter overrides, list of plusargs)
TESTS = [
    ("tb_spi_flash_reader", "tb_spi_flash_reader",
     ["sim/tb_spi_flash_reader.sv"], {}, [[]]),
    ("tb_spi_flash_reader_slow_flash", "tb_spi_flash_reader",
     ["sim/tb_spi_flash_reader.sv"], {"T_V_NS": "24.0"}, [[]]),
    ("tb_jtag_engine", "tb_jtag_engine", ["sim/tb_jtag_engine.sv"], {},
     [[]]),
    ("tb_jbin_decoder", "tb_jbin_decoder", ["sim/tb_jbin_decoder.sv"], {},
     [[]]),
    ("tb_top", "tb_top", ["sim/tb_top.sv"], {},
     [["+SCEN=%d" % i] for i in range(10)]),
]


def main(argv):
    pattern = argv[0] if argv else ""
    os.makedirs(BUILD, exist_ok=True)
    subprocess.run([sys.executable, os.path.join(HERE, "gen_vectors.py")],
                   check=True, cwd=ROOT)
    results = []
    for name, top, srcs, params, runs in TESTS:
        if pattern not in name:
            continue
        vvp = os.path.join(BUILD, name + ".vvp")
        cmd = ["iverilog", "-g2012", "-o", vvp, "-s", top]
        cmd += ["-P%s.%s=%s" % (top, k, v) for k, v in params.items()]
        cmd += RTL + MODELS + srcs
        comp = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
        if comp.returncode != 0:
            print(comp.stdout + comp.stderr)
            results.append((name, False))
            continue
        for plus in runs:
            label = name + ("" if not plus else " " + " ".join(plus))
            run = subprocess.run(["vvp", "-n", vvp] + plus, cwd=ROOT,
                                 capture_output=True, text=True)
            out = run.stdout + run.stderr
            ok = "TEST PASSED" in out and "TEST FAILED" not in out
            if not ok:
                print(out)
            print("%-45s %s" % (label, "PASS" if ok else "FAIL"))
            results.append((label, ok))
    failed = [n for n, ok in results if not ok]
    print("%d of %d passed" % (len(results) - len(failed), len(results)))
    return 1 if failed or not results else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
