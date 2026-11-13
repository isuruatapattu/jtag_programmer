# Extract the useful part of the VCS urg text reports.
#
#   tclsh scripts/extract_urg.tcl <urg report dir> <results dir>
#
# summarize.tcl sources this file and calls extract_urg itself.
# Writes into <results dir>:
#   cov_summary.txt    dashboard totals, the DUT rows of the hierarchy,
#                      covergroup totals and assertion totals
#   cov_uncovered.txt  report lines that mark uncovered items
#
# urg text layouts differ between versions, so this keeps whole report lines
# selected by keyword instead of parsing columns. Tcl 8.5 compatible.

proc urg_lines {path} {
    if {![file exists $path]} { return {} }
    set f [open $path r]
    set text [read $f]
    close $f
    set out {}
    foreach line [split $text "\n"] {
        set line [string trimright $line]
        if {$line ne ""} { lappend out $line }
    }
    return $out
}

# Append up to max lines of path matching re (all lines when re is "").
proc urg_take {fh title path re max} {
    puts $fh "== $title ([file tail $path])"
    if {![file exists $path]} {
        puts $fh "   (file not found)"
        return
    }
    set n 0
    foreach line [urg_lines $path] {
        if {$re ne "" && ![regexp -nocase -- $re $line]} { continue }
        puts $fh $line
        incr n
        if {$n >= $max} {
            puts $fh "   (cut at $max lines)"
            break
        }
    }
}

proc extract_urg {urg_dir res_dir} {
    set fh [open [file join $res_dir cov_summary.txt] w]
    if {![file isdirectory $urg_dir]} {
        puts $fh "urg report directory not found: $urg_dir"
        close $fh
        return 0
    }
    urg_take $fh "dashboard" [file join $urg_dir dashboard.txt] "" 30
    urg_take $fh "hierarchy, DUT rows" [file join $urg_dir hierarchy.txt] \
        {score|line|dut|u_slave|u_regs} 20
    urg_take $fh "covergroups" [file join $urg_dir groups.txt] \
        {score|cg_|cov_|group} 30
    urg_take $fh "assertions" [file join $urg_dir asserts.txt] \
        {total|assert|cover|fail|success|c_} 25
    close $fh

    set fh [open [file join $res_dir cov_uncovered.txt] w]
    puts $fh "Uncovered items from urg text reports in $urg_dir"
    set n 0
    foreach path [lsort [glob -nocomplain -directory $urg_dir mod*.txt grp*.txt]] {
        set hdr 0
        foreach line [urg_lines $path] {
            if {![regexp -nocase {not covered|uncovered|missing|\|\s*0\s*\||\s0\s+0\.00} $line]} {
                continue
            }
            if {!$hdr} {
                puts $fh "== [file tail $path]"
                set hdr 1
            }
            puts $fh $line
            incr n
            if {$n >= 400} { break }
        }
        if {$n >= 400} {
            puts $fh "(cut at 400 lines)"
            break
        }
    }
    if {$n == 0} { puts $fh "(no uncovered items found by keyword)" }
    close $fh
    return 1
}

if {[info exists argv0] && [file tail $argv0] eq "extract_urg.tcl"} {
    if {[llength $argv] != 2} {
        puts "usage: tclsh extract_urg.tcl <urg report dir> <results dir>"
        exit 2
    }
    extract_urg [lindex $argv 0] [lindex $argv 1]
}
