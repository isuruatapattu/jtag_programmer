#!/usr/bin/env python3
"""Golden equivalence check: libxsvf versus svf2jbin + jbin_model.

For every SVF file, this script

1. builds tools/golden/svf_record (libxsvf with a recording host) with gcc,
2. records the per-TCK trace that libxsvf produces,
3. converts the SVF with svf2jbin and expands it with jbin_model,
4. asserts that both traces are byte-identical and that the waits,
   frequency changes and TRST commands occur at the same TCK index.

Usage: run_golden.py [svf ...]
With no arguments it checks the reference bitstream SVF and every file in
sim/svf/.
"""

import glob
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.dirname(HERE)
ROOT = os.path.dirname(TOOLS)
REPO = os.path.dirname(os.path.dirname(ROOT))
LIBXSVF = os.path.join(REPO, "sw", "nexys_a7", "app_mb_svf_player",
                       "external", "libxsvf")
REFERENCE_SVF = os.path.join(REPO, "sw", "nexys_a7", "app_mb_svf_player",
                             "assets", "nexys_a7_01.svf")
BUILD = os.path.join(ROOT, "build", "golden")

sys.path.insert(0, TOOLS)
import jbin_model  # noqa: E402
import svf2jbin  # noqa: E402
from jbin_common import freq_to_div  # noqa: E402


def build_recorder():
    os.makedirs(BUILD, exist_ok=True)
    exe = os.path.join(BUILD, "svf_record.exe" if os.name == "nt"
                       else "svf_record")
    gcc = shutil.which("gcc") or shutil.which("cc")
    if not gcc:
        sys.exit("run_golden: no gcc/cc found on PATH")
    sources = [os.path.join(HERE, "svf_record.c")] + [
        os.path.join(LIBXSVF, n) for n in
        ("play.c", "svf.c", "tap.c", "statename.c", "memname.c")]
    cmd = [gcc, "-O2", "-std=gnu99", "-DLIBXSVF_WITHOUT_XSVF",
           "-DLIBXSVF_WITHOUT_SCAN", "-I", LIBXSVF, "-o", exe] + sources
    subprocess.run(cmd, check=True)
    return exe


def read_events(path, convert_freq):
    events = []
    with open(path) as f:
        for line in f:
            tck, kind, value = line.split()
            tck, value = int(tck), int(value)
            if kind == "FREQ" and convert_freq:
                kind, value = "DIV", freq_to_div(value)
            events.append((tck, kind, value))
    return events


def first_difference(a, b):
    n = min(len(a), len(b))
    step = 1 << 16
    for start in range(0, n, step):
        if a[start:start + step] != b[start:start + step]:
            for i in range(start, min(start + step, n)):
                if a[i] != b[i]:
                    return i
    return n


def check(exe, svf):
    name = os.path.splitext(os.path.basename(svf))[0]
    trc_ref = os.path.join(BUILD, name + ".libxsvf.trc")
    evt_ref = os.path.join(BUILD, name + ".libxsvf.events")
    jbin = os.path.join(BUILD, name + ".jbin")

    rec = subprocess.run([exe, svf, trc_ref, evt_ref],
                         capture_output=True, text=True)
    if rec.returncode != 0:
        print("  libxsvf failed:\n" + rec.stderr)
        return False

    data, _ = svf2jbin.convert(svf)
    with open(jbin, "wb") as f:
        f.write(data)
    model = jbin_model.Model(data).run()

    with open(trc_ref, "rb") as f:
        ref = f.read()
    ok = True
    if ref != bytes(model.trace):
        idx = first_difference(ref, model.trace)
        print("  TRACE MISMATCH at TCK %d (libxsvf %d TCK, jbin %d TCK)"
              % (idx, len(ref), len(model.trace)))
        ok = False
    ref_events = read_events(evt_ref, convert_freq=True)
    if ref_events != model.events:
        print("  EVENT MISMATCH\n    libxsvf: %s\n    jbin:    %s"
              % (ref_events, model.events))
        ok = False
    print("  %s: %d TCK, %d TDO checks, %d events, %d JBIN bytes"
          % ("PASS" if ok else "FAIL", len(ref),
             sum(ref.count(bytes([v])) for v in range(8, 16)),
             len(ref_events), len(data)))
    return ok


def main(argv):
    svfs = argv or [REFERENCE_SVF] + sorted(
        glob.glob(os.path.join(ROOT, "sim", "svf", "*.svf")))
    exe = build_recorder()
    failures = 0
    for svf in svfs:
        print(os.path.relpath(svf, REPO))
        if not check(exe, svf):
            failures += 1
    print("%d of %d SVF files match libxsvf" % (len(svfs) - failures,
                                               len(svfs)))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
