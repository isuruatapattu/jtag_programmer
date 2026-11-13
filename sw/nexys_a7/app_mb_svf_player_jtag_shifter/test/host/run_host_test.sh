#!/bin/sh
# Builds svf_player.c and libxsvf for the host against stub Xilinx headers,
# a model of AXI GPIO, the jtag_shifter registers and a TAP, then checks
# that the shifter and GPIO paths drive identical TCK edges and TDO results.
set -e
here=$(cd "$(dirname "$0")" && pwd)
app="$here/../.."
x="$app/external/libxsvf"
out="${TMPDIR:-/tmp}/jsh_host_test"
${CC:-gcc} -std=gnu99 -O1 -Wall -Wno-unused-function \
    -I"$here/stubs" -I"$app" -I"$x" \
    "$here/host_test.c" "$x/svf.c" "$x/xsvf.c" "$x/tap.c" "$x/statename.c" \
    "$x/memname.c" "$x/play.c" "$x/scan.c" -o "$out"
"$out"
