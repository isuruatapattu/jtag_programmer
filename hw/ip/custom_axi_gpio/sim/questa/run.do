# Run by sim/run.sh: vsim -c -onfinish stop ... -do questa/run.do
# COV_UCDB is set by run.sh only for coverage runs.

run -all
if {[info exists ::env(COV_UCDB)] && $::env(COV_UCDB) ne ""} {
    coverage save $::env(COV_UCDB)
}
quit -f
