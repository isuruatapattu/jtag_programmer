#!/usr/bin/env bash
# Open the Questa GUI on one test, with JTAG pins labeled in the wave window.
#
#   bash sim/gui.sh                         # t_sw_loopback (JA1 TCK wired to JA7 TDO)
#   bash sim/gui.sh t_sw_test_outputs       # walks TCK, TMS, TDI, then all four pins
#   bash sim/gui.sh t_sw_configure --seed 1
#
# Useful tests: t_sw_loopback, t_sw_test_outputs, t_sw_configure,
# t_sw_write_read_tdo. The window stays open after the test. Add more signals
# from dut or axi; they were logged, so history is already there.
#
# Needs a display. From a remote shell: ssh -X, then run this.

set -u

SIM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IP_DIR="$(cd "$SIM_DIR/.." && pwd)"

QUESTA_VLOG_FLAGS="-sv -timescale 1ns/1ps"
SIM_TIMEOUT_NS=5000000
TOP=tb_axi_gpio_jtag

RTL_FILES=(
    "$IP_DIR/rtl/axi_lite_slave.v"
    "$IP_DIR/rtl/gpio_jtag_regs.v"
    "$IP_DIR/rtl/axi_gpio_jtag.v"
)
TB_FILES=(
    "$SIM_DIR/tb/axi_lite_if.sv"
    "$SIM_DIR/tb/axi_lite_checker.sv"
    "$SIM_DIR/tb/tb_axi_gpio_jtag.sv"
)

usage() {
    sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 2
}

msg() { echo "[gui.sh] $*"; }

TEST=t_sw_loopback
SEED=1
while [ $# -gt 0 ]; do
    case "$1" in
        --seed) SEED=$2; shift 2 ;;
        -h|--help) usage ;;
        *) TEST=$1; shift ;;
    esac
done

[ -f "$SIM_DIR/env.sh" ] && . "$SIM_DIR/env.sh"

if [ -z "${DISPLAY:-}" ]; then
    msg "DISPLAY is not set. The GUI needs a screen (ssh -X from your desktop)."
fi
command -v vlog >/dev/null 2>&1 || { msg "ERROR: vlog not on PATH. Load Questa in sim/env.sh."; exit 1; }
command -v vsim >/dev/null 2>&1 || { msg "ERROR: vsim not on PATH. Load Questa in sim/env.sh."; exit 1; }

BUILD="$SIM_DIR/build/questa/gui"
rm -rf "$BUILD"
mkdir -p "$BUILD"

msg "compile $TEST seed=$SEED"
(
    cd "$BUILD" &&
    vlib work &&
    vlog -work work $QUESTA_VLOG_FLAGS "${RTL_FILES[@]}" "${TB_FILES[@]}"
) || { msg "ERROR: compile failed"; exit 1; }

msg "starting Questa GUI"
cd "$BUILD"
vsim -gui -voptargs="+acc" -onfinish stop -lib work "$TOP" \
    "+TEST=$TEST" "+SEED=$SEED" "+TIMEOUT_NS=$SIM_TIMEOUT_NS" \
    -do "$SIM_DIR/questa/wave_jtag.do"
