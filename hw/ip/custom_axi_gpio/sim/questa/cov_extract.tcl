# Coverage extraction for Questa. Run by sim/run.sh:
#   COV_OUT=<results dir> vsim -c -viewcov merged.ucdb -do questa/cov_extract.tcl
#
# Writes into $COV_OUT:
#   cov_summary_raw.txt    code coverage summary of the DUT (tb_axi_gpio_jtag/dut)
#   cov_cvg_raw.txt        covergroup bins
#   cov_assert_raw.txt     assertion and cover directive results
#   cov_uncovered_raw.txt  uncovered code items in the DUT
#   cov_extract.log        which command variant worked for each file
#
# Report options differ between Questa versions, so each file tries several
# variants and keeps the first that runs and writes a non-empty file.

set out_dir "."
if {[info exists ::env(COV_OUT)] && $::env(COV_OUT) ne ""} {
    set out_dir $::env(COV_OUT)
}
set dut /tb_axi_gpio_jtag/dut
set log [open [file join $out_dir cov_extract.log] w]

proc report_to {log out_dir name variants} {
    set path [file join $out_dir $name]
    foreach args $variants {
        foreach opt {-output -file} {
            file delete -force $path
            set cmd [concat coverage report $args [list $opt $path]]
            if {[catch {eval $cmd} err]} {
                puts $log "TRY_FAILED $name: $cmd: [string trim $err]"
                continue
            }
            if {[file exists $path] && [file size $path] > 0} {
                puts $log "EXTRACT_OK $name: $cmd"
                return 1
            }
            puts $log "TRY_FAILED $name: $cmd: no output"
        }
    }
    puts $log "WARN $name: every variant failed"
    return 0
}

report_to $log $out_dir cov_summary_raw.txt [list \
    [list -summary -instance=$dut -recursive -code bcesft] \
    [list -instance=$dut -recursive -code bcesft] \
    [list -summary -instance=$dut -recursive] \
    [list -summary] \
]
report_to $log $out_dir cov_cvg_raw.txt [list \
    [list -cvg -details] \
    [list -cvg] \
]
report_to $log $out_dir cov_assert_raw.txt [list \
    [list -assert -directive -details] \
    [list -assert -details] \
    [list -assert] \
]
report_to $log $out_dir cov_uncovered_raw.txt [list \
    [list -zeros -details -instance=$dut -recursive -code bcesft] \
    [list -zeros -details -instance=$dut -recursive] \
    [list -zeros -details] \
]

close $log
quit -f
