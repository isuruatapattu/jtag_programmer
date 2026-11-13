# Summarize a simulation run into files small enough to send back.
#
#   tclsh scripts/summarize.tcl <questa|vcs> <results dir> <ip dir>
#
# or, inside vsim, with SUM_TOOL, SUM_RES and SUM_IP set in the environment.
# Writes into <results dir>:
#   summary.txt        about 150 lines: versions, lint and compile messages,
#                      test results, assertion failures, coverage, mutants
#   trace_status.txt   one line per spec ID: sim, FAIL, NOT_RUN or n/a
#   cov_uncovered.txt  uncovered coverage items (Questa; VCS via extract_urg)
#
# It relies only on the fixed lines printed by tb_axi_gpio_jtag.sv
# (TEST_START, TEST_RESULT, ERROR, ASSERT_FAIL, SIM_SUMMARY), on tool error
# and warning prefixes, and on doc/traceability.md. Tcl 8.5 compatible.

if {[info exists ::env(SUM_TOOL)] && [info exists ::env(SUM_RES)] && [info exists ::env(SUM_IP)]} {
    set tool $::env(SUM_TOOL)
    set res  $::env(SUM_RES)
    set ip   $::env(SUM_IP)
} elseif {[info exists argv] && [llength $argv] == 3} {
    foreach {tool res ip} $argv break
} else {
    puts "usage: tclsh summarize.tcl <questa|vcs> <results dir> <ip dir>"
    exit 2
}

set script_dir [file dirname [file normalize [info script]]]

set ERR_RE  {^(# )?\*\* (Error|Fatal)|^Error-\[}
set WARN_RE {^(# )?\*\* Warning|^Warning-\[|^Lint-\[}

proc lines_of {path} {
    if {![file exists $path]} { return {} }
    set f [open $path r]
    fconfigure $f -translation auto
    set text [read $f]
    close $f
    set out {}
    foreach line [split $text "\n"] { lappend out [string trimright $line] }
    return $out
}

# Remove the "# " transcript prefix of Questa.
proc plain {line} {
    regsub {^# ?} $line "" line
    return $line
}

set out {}
proc emit {args} {
    global out
    lappend out [join $args " "]
}

proc emit_capped {lines max {indent "   "}} {
    set n 0
    foreach line $lines {
        if {$n >= $max} {
            emit "${indent}... [expr {[llength $lines] - $max}] more"
            break
        }
        emit "$indent$line"
        incr n
    }
}

proc uniq {lines} {
    set seen [dict create]
    set out {}
    foreach l $lines {
        if {[dict exists $seen $l]} { continue }
        dict set seen $l 1
        lappend out $l
    }
    return $out
}

set fail_reasons {}
proc verdict_fail {why} {
    global fail_reasons
    lappend fail_reasons $why
}

# ---------------------------------------------------------------- header
emit "axi_gpio_jtag simulation summary, tool=$tool"
emit "generated [clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}]"
foreach line [lrange [lines_of [file join $res tool_version.txt]] 0 7] {
    if {$line ne ""} { emit "   $line" }
}

# ---------------------------------------------------------------- lint and compile
emit ""
emit "== Lint and compile"
foreach name {lint.log compile.log compile_cov.log} {
    set path [file join $res $name]
    if {![file exists $path]} {
        emit "$name: not run"
        if {$name ne "compile_cov.log"} { verdict_fail "$name not run" }
        continue
    }
    set errs {}
    set warns {}
    foreach line [lines_of $path] {
        if {[regexp -- $ERR_RE $line]} { lappend errs [plain $line] }
        if {[regexp -- $WARN_RE $line]} { lappend warns [plain $line] }
    }
    emit "$name: [llength $errs] errors, [llength $warns] warnings"
    emit_capped [uniq $errs] 8
    emit_capped [uniq $warns] 12
    if {[llength $errs] > 0} { verdict_fail "$name has errors" }
}

# ---------------------------------------------------------------- simulation logs
set tests {}
set trace_rows {}
foreach line [lines_of [file join $ip doc traceability.md]] {
    if {![regexp {^\|\s*(GPIO-[A-Z]+-[0-9]+)\s*\|} $line]} { continue }
    set cells {}
    foreach c [lrange [split $line "|"] 1 end-1] { lappend cells [string trim $c] }
    lappend trace_rows $cells
    foreach t [regexp -all -inline {t_[a-z0-9_]+} [lindex $cells 3]] {
        if {[lsearch -exact $tests $t] < 0} { lappend tests $t }
    }
}

set reg_logs [lsort [glob -nocomplain -directory $res sim_s*.log]]
set cov_logs [lsort [glob -nocomplain -directory $res sim_cov_s*.log]]
set one_logs [lsort [glob -nocomplain -directory $res sim_one_*.log]]
set logs [concat $reg_logs $cov_logs]
if {[llength $logs] == 0} { set logs $one_logs }

# result(test) = list of "log:PASS|FAIL"
array set result {}
array set assert_ids {}
set err_lines {}
set err_ids [dict create]
set tool_errs {}
set elab_warns {}
set total_assert 0
emit ""
emit "== Simulation ([llength $logs] logs)"
if {[llength $logs] == 0} {
    emit "no simulation logs found"
    verdict_fail "no simulation logs"
}
foreach path $logs {
    set log [file tail $path]
    set summary ""
    set started {}
    foreach raw [lines_of $path] {
        set line [plain $raw]
        if {[regexp {TEST_START (\S+)} $line -> t]} {
            lappend started $t
        } elseif {[regexp {TEST_RESULT (\S+) (PASS|FAIL)} $line -> t r]} {
            lappend result($t) "$log:$r"
        } elseif {[regexp {SIM_SUMMARY (.*)$} $line -> s]} {
            set summary $s
        }
        if {[regexp {ASSERT_FAIL (\S+)} $line -> id]} {
            if {![info exists assert_ids($id)]} { set assert_ids($id) 0 }
            incr assert_ids($id)
            incr total_assert
        } elseif {[regexp -- $::ERR_RE $raw]} {
            lappend tool_errs "$log: $line"
        } elseif {[regexp -- $::WARN_RE $raw]} {
            lappend elab_warns $line
        }
        if {[regexp {^ERROR (\S+) (.*)$} $line -> t m]} {
            lappend err_lines "$log $t: $m"
            foreach id [regexp -all -inline {GPIO-[A-Z]+-[0-9]+} $m] {
                dict set err_ids $id 1
            }
        }
    }
    if {$summary eq ""} {
        emit "$log: INCOMPLETE (no SIM_SUMMARY; last test started: [lindex $started end])"
        verdict_fail "$log incomplete"
    } else {
        emit "$log: $summary"
        if {![regexp {fail=0 assert_fail=0} $summary]} { verdict_fail "$log has failures" }
    }
}
if {[llength $tool_errs] > 0} {
    emit "tool errors during simulation:"
    emit_capped [uniq $tool_errs] 6
    verdict_fail "tool errors during simulation"
}
if {[llength $elab_warns] > 0} {
    set u [uniq $elab_warns]
    emit "simulator warnings ([llength $u] distinct):"
    emit_capped $u 8
}

emit ""
emit "== Tests"
array set test_state {}
foreach t $tests {
    if {![info exists result($t)]} {
        set test_state($t) NOT_RUN
        emit [format "%-22s NOT_RUN" $t]
        verdict_fail "$t not run"
        continue
    }
    set bad {}
    foreach r $result($t) {
        if {[string match *:FAIL $r]} { lappend bad [lindex [split $r :] 0] }
    }
    set n [llength $result($t)]
    if {[llength $bad] == 0} {
        set test_state($t) PASS
        emit [format "%-22s PASS (%d runs)" $t $n]
    } else {
        set test_state($t) FAIL
        emit [format "%-22s FAIL in %d of %d runs: %s" $t [llength $bad] $n [join $bad " "]]
    }
}
foreach t [lsort [array names result]] {
    if {[lsearch -exact $tests $t] < 0} { emit "$t: not in traceability.md" }
}

if {$total_assert > 0} {
    emit ""
    emit "== Assertion failures by spec ID ($total_assert total)"
    foreach id [lsort [array names assert_ids]] { emit "   $id: $assert_ids($id)" }
}
if {[llength $err_lines] > 0} {
    emit ""
    emit "== First check failures ([llength $err_lines] total)"
    emit_capped $err_lines 15
}

# ---------------------------------------------------------------- trace status
set all_pass [expr {[llength $logs] > 0}]
foreach t $tests {
    if {$test_state($t) ne "PASS"} { set all_pass 0 }
}
set tf [open [file join $res trace_status.txt] w]
set counts [dict create]
set not_ok {}
foreach cells $trace_rows {
    set id [lindex $cells 0]
    set sim [lindex $cells 3]
    set st sim
    set why ""
    if {$sim eq "-" || $sim eq ""} {
        set st n/a
    } else {
        foreach t [regexp -all -inline {t_[a-z0-9_]+} $sim] {
            if {$test_state($t) eq "NOT_RUN" && $st eq "sim"} {
                set st NOT_RUN
                set why "$t not run"
            } elseif {$test_state($t) eq "FAIL"} {
                set st FAIL
                set why "$t failed"
            }
        }
        if {[info exists assert_ids($id)]} {
            set st FAIL
            set why "$assert_ids($id) assertion failures"
        }
        if {[dict exists $err_ids $id]} {
            set st FAIL
            set why "named in a check failure"
        }
        if {[regexp {\mall\M} $sim] && !$all_pass && $st eq "sim"} {
            set st FAIL
            set why "not every test passed"
        }
        if {[llength $logs] == 0} {
            set st NOT_RUN
            set why "no simulation logs"
        }
    }
    puts $tf [string trimright [format "%-14s %-8s %s" $id $st $why]]
    dict incr counts $st
    if {$st ne "sim" && $st ne "n/a"} { lappend not_ok "$id $st $why" }
}
close $tf
emit ""
set c {}
foreach k [lsort [dict keys $counts]] { lappend c "$k=[dict get $counts $k]" }
emit "== Trace status ([llength $trace_rows] IDs: [join $c {, }]), details in trace_status.txt"
emit_capped $not_ok 15

# ---------------------------------------------------------------- coverage
emit ""
emit "== Coverage"
proc emit_matching {path re max} {
    if {![file exists $path]} {
        emit "   [file tail $path]: not found"
        return 0
    }
    set hits {}
    foreach line [lines_of $path] {
        if {$line ne "" && [regexp -nocase -- $re $line]} { lappend hits [string trim $line] }
    }
    emit "   -- [file tail $path]"
    emit_capped $hits $max "   "
    return 1
}
set cov_found 0
if {$tool eq "questa"} {
    set cov_found [emit_matching [file join $res cov_summary_raw.txt] \
        {statement|branch|condition|expression|toggle|fsm|total} 16]
    emit_matching [file join $res cov_cvg_raw.txt] \
        {^\s*(type|covergroup|coverpoint|cross)|zero|total} 30
    emit_matching [file join $res cov_assert_raw.txt] \
        {total|c_b_stall|c_r_stall|c_same_cycle|zero|fail} 10
    set warn [emit_matching [file join $res cov_extract.log] {^WARN } 5]
    set src [file join $res cov_uncovered_raw.txt]
    if {[file exists $src]} {
        file copy -force $src [file join $res cov_uncovered.txt]
    }
} else {
    source [file join $script_dir extract_urg.tcl]
    if {[extract_urg [file join $res urg] $res]} {
        set cov_found 1
        foreach line [lines_of [file join $res cov_summary.txt]] {
            if {$line ne ""} { lappend cl $line }
        }
        if {[info exists cl]} { emit_capped $cl 45 }
    } else {
        emit "   urg reports not found in [file join $res urg]"
    }
}
if {!$cov_found} { verdict_fail "no coverage report" }
if {[file exists [file join $res cov_uncovered.txt]]} {
    set n [llength [lines_of [file join $res cov_uncovered.txt]]]
    emit "   cov_uncovered.txt: $n lines"
}

# ---------------------------------------------------------------- mutants
emit ""
set mpath [file join $res mutants.txt]
if {![file exists $mpath]} {
    emit "== Mutants: not run"
    verdict_fail "mutants not run"
} else {
    set total 0
    set killed 0
    set mlines {}
    foreach line [lines_of $mpath] {
        if {$line eq ""} { continue }
        incr total
        if {[lindex [split $line " "] 1] eq "KILLED"} { incr killed }
        lappend mlines $line
    }
    emit "== Mutants: $killed of $total killed"
    emit_capped $mlines 20
    if {$total == 0 || $killed != $total} { verdict_fail "not every mutant killed" }
}

# ---------------------------------------------------------------- verdict
emit ""
if {[llength $fail_reasons] == 0} {
    emit "VERDICT PASS (coverage numbers above still need review against the exit gate)"
} else {
    emit "VERDICT FAIL: [join [uniq $fail_reasons] {; }]"
}

set f [open [file join $res summary.txt] w]
fconfigure $f -translation lf
puts $f [join $out "\n"]
close $f
puts "wrote [file join $res summary.txt] ([llength $out] lines)"
