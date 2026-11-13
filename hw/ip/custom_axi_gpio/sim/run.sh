#!/usr/bin/env bash
# Single entry point for the axi_gpio_jtag simulations.
#
#   bash sim/run.sh <questa|vcs> <step> [options]
#
# Steps
#   lint      lint the RTL as Verilog-2001
#   sim       compile and run one test (--test, default all) with one seed
#   regress   run all tests once per seed in --seeds
#   cov       regress with code and functional coverage, merge, extract
#   mutants   run all tests against every broken RTL copy in sim/mutants
#   summary   write results/<tool>/summary.txt from the logs
#   all       lint, regress, cov, mutants, summary
#
# Options
#   --test NAME       test for "sim" (default all)
#   --seed N          seed for "sim" (default 1)
#   --seeds "1 2 3"   seeds for regress and cov (default "1 2 3 4 5")
#   --build-dir DIR   build directory (default sim/build/<tool>)
#   --dump            write tb_axi_gpio_jtag.vcd in the build directory
#
# Results go to sim/results/<tool>/. Send back summary.txt.
# Tools are loaded by sim/env.sh if it exists (see env.sh.example).

set -u

SIM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IP_DIR="$(cd "$SIM_DIR/.." && pwd)"

# ---- Tool flags. Change them here if your installed version differs. ----
QUESTA_VLOG_FLAGS="-sv -timescale 1ns/1ps"
QUESTA_LINT_FLAGS="-vlog01compat -lint"
QUESTA_COVER_FLAGS="+cover=bcesft"
QUESTA_VSIM_FLAGS="-c -onfinish stop"
QUESTA_VSIM_COV_FLAGS="-coverage"
VCS_FLAGS="-full64 -sverilog -timescale=1ns/1ps"
VCS_LINT_FLAGS="-full64 +v2k +lint=all,noVCDE -timescale=1ns/1ps"
VCS_CM="line+cond+branch+tgl+assert"
URG_FLAGS="-full64 -format text"
SIM_TIMEOUT_NS=5000000
# ---------------------------------------------------------------------------

TOP=tb_axi_gpio_jtag
RTL_TOP=axi_gpio_jtag
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
    sed -n '2,23p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 2
}

msg() { echo "[run.sh] $*"; }

[ $# -ge 2 ] || usage
TOOL=$1
STEP=$2
shift 2
case "$TOOL" in questa|vcs) ;; *) usage ;; esac
case "$STEP" in lint|sim|regress|cov|mutants|summary|all) ;; *) usage ;; esac

TEST=all
SEED=1
SEEDS="1 2 3 4 5"
BUILD=""
DUMP=""
while [ $# -gt 0 ]; do
    case "$1" in
        --test)      TEST=$2; shift 2 ;;
        --seed)      SEED=$2; shift 2 ;;
        --seeds)     SEEDS=$2; shift 2 ;;
        --build-dir) BUILD=$2; shift 2 ;;
        --dump)      DUMP="+DUMP"; shift ;;
        *)           usage ;;
    esac
done

[ -f "$SIM_DIR/env.sh" ] && . "$SIM_DIR/env.sh"

[ -n "$BUILD" ] || BUILD="$SIM_DIR/build/$TOOL"
mkdir -p "$BUILD"
BUILD="$(cd "$BUILD" && pwd)"
RES="$SIM_DIR/results/$TOOL"
mkdir -p "$RES"

need() {
    if ! command -v "$1" >/dev/null 2>&1; then
        msg "ERROR: '$1' not found on PATH. Load the tool in sim/env.sh."
        exit 1
    fi
}

if [ "$TOOL" = questa ]; then
    need vlog; need vsim
else
    need vcs
fi

# t_random replays vectors/random_seed<N>.txt, or seed 1 if there is none.
vec_for_seed() {
    local f="$SIM_DIR/vectors/random_seed$1.txt"
    [ -f "$f" ] || f="$SIM_DIR/vectors/random_seed1.txt"
    echo "$f"
}

record_version() {
    {
        echo "date: $(date)"
        echo "host: $(uname -n)"
        if [ "$TOOL" = questa ]; then
            vsim -version 2>&1 | head -n 3
        else
            vcs -ID 2>&1 | head -n 5
            command -v urg >/dev/null 2>&1 && echo "urg: $(command -v urg)"
        fi
        command -v tclsh >/dev/null 2>&1 && echo "tclsh: $(echo 'puts [info patchlevel]' | tclsh)"
    } > "$RES/tool_version.txt" 2>&1
}

# compile <dir> <log> <cov 0|1> <rtl files...>
compile() {
    local dir=$1 logf=$2 cov=$3
    shift 3
    rm -rf "$dir"
    mkdir -p "$dir"
    if [ "$TOOL" = questa ]; then
        local cf=""
        [ "$cov" = 1 ] && cf="$QUESTA_COVER_FLAGS"
        (
            cd "$dir" &&
            vlib work &&
            vlog -work work $QUESTA_VLOG_FLAGS $cf "$@" &&
            vlog -work work $QUESTA_VLOG_FLAGS "${TB_FILES[@]}"
        ) > "$logf" 2>&1
    else
        local cf=""
        [ "$cov" = 1 ] && cf="-cm $VCS_CM -cm_hier $SIM_DIR/vcs/cm_hier.cfg"
        (
            cd "$dir" &&
            vcs $VCS_FLAGS $cf -top "$TOP" -o simv "$@" "${TB_FILES[@]}"
        ) > "$logf" 2>&1
    fi
    local rc=$?
    if [ $rc -ne 0 ]; then
        msg "ERROR: compile failed, see $logf"
    fi
    return $rc
}

# simulate <dir> <log> <test> <seed> <cov 0|1>
simulate() {
    local dir=$1 logf=$2 test=$3 seed=$4 cov=$5
    local args="+TEST=$test +SEED=$seed +VEC=$(vec_for_seed "$seed") +TIMEOUT_NS=$SIM_TIMEOUT_NS $DUMP"
    if [ "$TOOL" = questa ]; then
        local cf="" ucdb=""
        if [ "$cov" = 1 ]; then
            cf="$QUESTA_VSIM_COV_FLAGS"
            ucdb="$dir/cov_s$seed.ucdb"
        fi
        (
            cd "$dir" &&
            COV_UCDB="$ucdb" vsim $QUESTA_VSIM_FLAGS $cf -lib work "$TOP" $args \
                -do "$SIM_DIR/questa/run.do"
        ) < /dev/null > "$logf" 2>&1
    else
        local cf=""
        [ "$cov" = 1 ] && cf="-cm $VCS_CM -cm_name s$seed"
        (
            cd "$dir" &&
            ./simv $args $cf
        ) < /dev/null > "$logf" 2>&1
    fi
    if grep -a -q 'SIM_SUMMARY ' "$logf"; then
        msg "$(grep -a 'SIM_SUMMARY ' "$logf" | tail -n 1 | sed 's/^# //')  ($logf)"
    else
        msg "ERROR: no SIM_SUMMARY in $logf"
    fi
}

step_lint() {
    msg "lint"
    local dir="$BUILD/lint"
    rm -rf "$dir"
    mkdir -p "$dir"
    if [ "$TOOL" = questa ]; then
        (
            cd "$dir" &&
            vlib work &&
            vlog -work work $QUESTA_LINT_FLAGS "${RTL_FILES[@]}"
        ) > "$RES/lint.log" 2>&1
    else
        (
            cd "$dir" &&
            vcs $VCS_LINT_FLAGS -top "$RTL_TOP" -o lint_simv "${RTL_FILES[@]}"
        ) > "$RES/lint.log" 2>&1
    fi
    msg "lint exit code $? ($RES/lint.log)"
}

step_sim() {
    msg "sim test=$TEST seed=$SEED"
    compile "$BUILD/sim" "$RES/compile.log" 0 "${RTL_FILES[@]}" || return 1
    if [ "$TEST" = all ]; then
        simulate "$BUILD/sim" "$RES/sim_s$SEED.log" all "$SEED" 0
    else
        simulate "$BUILD/sim" "$RES/sim_one_${TEST}_s$SEED.log" "$TEST" "$SEED" 0
    fi
}

step_regress() {
    msg "regress seeds=$SEEDS"
    rm -f "$RES"/sim_s*.log
    compile "$BUILD/sim" "$RES/compile.log" 0 "${RTL_FILES[@]}" || return 1
    local s
    for s in $SEEDS; do
        simulate "$BUILD/sim" "$RES/sim_s$s.log" all "$s" 0
    done
}

step_cov() {
    msg "cov seeds=$SEEDS"
    local dir="$BUILD/cov"
    rm -f "$RES"/sim_cov_s*.log "$RES"/cov_*.txt "$RES"/cov_*.log
    rm -rf "$RES/urg"
    compile "$dir" "$RES/compile_cov.log" 1 "${RTL_FILES[@]}" || return 1
    local s
    for s in $SEEDS; do
        simulate "$dir" "$RES/sim_cov_s$s.log" all "$s" 1
    done
    if [ "$TOOL" = questa ]; then
        local ucdbs=()
        for s in $SEEDS; do
            [ -f "$dir/cov_s$s.ucdb" ] && ucdbs+=("$dir/cov_s$s.ucdb")
        done
        if [ ${#ucdbs[@]} -eq 0 ]; then
            msg "ERROR: no UCDB files were saved"
            return 1
        fi
        (
            cd "$dir" &&
            { vcover merge -out merged.ucdb "${ucdbs[@]}" ||
              vcover merge merged.ucdb "${ucdbs[@]}"; }
        ) > "$RES/cov_merge.log" 2>&1
        if [ ! -f "$dir/merged.ucdb" ]; then
            msg "ERROR: vcover merge failed, see $RES/cov_merge.log"
            return 1
        fi
        vcover report -details "$dir/merged.ucdb" > "$RES/cov_vcover_report.txt" 2>&1
        (
            cd "$dir" &&
            COV_OUT="$RES" vsim -c -viewcov merged.ucdb -do "$SIM_DIR/questa/cov_extract.tcl"
        ) < /dev/null > "$RES/cov_extract_vsim.log" 2>&1
        msg "coverage extracted to $RES/cov_*_raw.txt"
    else
        need urg
        (
            cd "$dir" &&
            urg $URG_FLAGS -dir simv.vdb -report urgReport
        ) < /dev/null > "$RES/cov_urg.log" 2>&1
        if [ -d "$dir/urgReport" ]; then
            cp -r "$dir/urgReport" "$RES/urg"
            msg "urg reports copied to $RES/urg"
        else
            msg "ERROR: urg wrote no report, see $RES/cov_urg.log"
        fi
    fi
}

# classify <log> -> KILLED|SURVIVED|ERROR <detail>
classify() {
    local line fl af
    line=$(grep -a 'SIM_SUMMARY ' "$1" | tail -n 1)
    if [ -z "$line" ]; then
        echo "ERROR no_SIM_SUMMARY"
        return
    fi
    fl=$(echo "$line" | sed -n 's/.* fail=\([0-9]*\).*/\1/p')
    af=$(echo "$line" | sed -n 's/.*assert_fail=\([0-9]*\).*/\1/p')
    if [ -z "$fl" ] || [ -z "$af" ]; then
        echo "ERROR bad_SIM_SUMMARY"
    elif [ "$fl" -gt 0 ] || [ "$af" -gt 0 ]; then
        echo "KILLED fail=$fl assert_fail=$af"
    else
        echo "SURVIVED fail=0 assert_fail=0"
    fi
}

step_mutants() {
    msg "mutants"
    local manifest="$SIM_DIR/mutants/manifest.txt"
    local out="$RES/mutants.txt"
    rm -f "$RES"/sim_mut_*.log "$RES"/compile_mut_*.log
    if [ ! -f "$manifest" ]; then
        msg "ERROR: $manifest not found (run python sim/mutants/gen_mutants.py)"
        echo "ERROR no manifest" > "$out"
        return 1
    fi
    : > "$out"
    local name file desc f rtl result
    while IFS='|' read -r name file desc <&3; do
        case "$name" in ''|'#'*) continue ;; esac
        rtl=()
        for f in "${RTL_FILES[@]}"; do
            if [ "$(basename "$f")" = "$file" ]; then
                rtl+=("$SIM_DIR/mutants/$name/$file")
            else
                rtl+=("$f")
            fi
        done
        if [ ! -f "$SIM_DIR/mutants/$name/$file" ]; then
            result="ERROR missing_file"
        elif ! compile "$BUILD/mut_$name" "$RES/compile_mut_$name.log" 0 "${rtl[@]}"; then
            result="ERROR compile"
        else
            simulate "$BUILD/mut_$name" "$RES/sim_mut_$name.log" all 1 0
            result=$(classify "$RES/sim_mut_$name.log")
            rm -rf "$BUILD/mut_$name"
        fi
        msg "mutant $name: $result"
        echo "$name $result | $desc" >> "$out"
    done 3< "$manifest"
}

write_basic_summary() {
    local f
    {
        echo "summary_basic.txt for $TOOL (written without tclsh)"
        cat "$RES/tool_version.txt" 2>/dev/null
        for f in "$RES"/lint.log "$RES"/compile.log "$RES"/compile_cov.log; do
            [ -f "$f" ] || continue
            echo "== $(basename "$f"): $(grep -a -c -E '^(# )?\*\* (Error|Fatal)|^Error-\[' "$f") errors," \
                 "$(grep -a -c -E '^(# )?\*\* Warning|^Warning-\[|^Lint-\[' "$f") warnings"
            grep -a -E '^(# )?\*\* (Error|Fatal)|^Error-\[' "$f" | head -n 10
        done
        for f in "$RES"/sim_s*.log "$RES"/sim_cov_s*.log "$RES"/sim_one_*.log; do
            [ -f "$f" ] || continue
            echo "== $(basename "$f")"
            grep -a -E 'TEST_RESULT .* FAIL|ASSERT_FAIL|SIM_SUMMARY|(^|# )ERROR ' "$f" | head -n 20
        done
        [ -f "$RES/mutants.txt" ] && { echo "== mutants"; cat "$RES/mutants.txt"; }
    } > "$RES/summary_basic.txt" 2>&1
}

step_summary() {
    msg "summary"
    write_basic_summary
    if command -v tclsh >/dev/null 2>&1; then
        tclsh "$SIM_DIR/scripts/summarize.tcl" "$TOOL" "$RES" "$IP_DIR"
    elif [ "$TOOL" = questa ]; then
        (
            cd "$BUILD" &&
            SUM_TOOL="$TOOL" SUM_RES="$RES" SUM_IP="$IP_DIR" \
                vsim -c -do "source {$SIM_DIR/scripts/summarize.tcl}; quit -f"
        ) < /dev/null > "$RES/summarize_vsim.log" 2>&1
    else
        msg "tclsh not found: only $RES/summary_basic.txt was written"
        return 0
    fi
    if [ -f "$RES/summary.txt" ]; then
        grep -a '^VERDICT' "$RES/summary.txt"
        msg "send back $RES/summary.txt"
    else
        msg "ERROR: summary.txt was not written; send back $RES/summary_basic.txt"
    fi
}

record_version

case "$STEP" in
    lint)    step_lint ;;
    sim)     step_sim ;;
    regress) step_regress ;;
    cov)     step_cov ;;
    mutants) step_mutants ;;
    summary) step_summary ;;
    all)
        step_lint
        step_regress
        step_cov
        step_mutants
        step_summary
        ;;
esac
exit 0
