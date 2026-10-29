# Run the testbench suite in Vivado xsim.
#
#   cd hw/jtag_programmer_fpga_only
#   vivado -mode batch -source sim/run_sim.tcl                      ;# all tests, XPM FIFO
#   vivado -mode batch -source sim/run_sim.tcl -tclargs tb_top      ;# name filter
#   vivado -mode batch -source sim/run_sim.tcl -tclargs "" inferred ;# inferred FIFO
#
# Works from a Vivado Tcl shell as well (xvlog/xelab/xsim must be on PATH,
# which the Vivado settings script arranges). Needs Python 3 on PATH for
# sim/gen_vectors.py. Logs go to build/xsim/. The project path must not
# contain spaces (it is passed to the testbenches as +VEC=<dir>).

set root [file normalize [file join [file dirname [info script]] ..]]
cd $root

set filter   [expr {[llength $argv] > 0 ? [lindex $argv 0] : ""}]
set fifo_xpm [expr {[llength $argv] > 1 && [lindex $argv 1] eq "inferred" ? 0 : 1}]
set work     [file join $root build xsim]
set vec_dir  [file join $root build sim vectors]
file mkdir $work

set python [expr {[auto_execok python3] ne "" ? "python3" : "python"}]
exec $python [file join $root sim gen_vectors.py] >@ stdout

set rtl {
    rtl/crc32.sv rtl/byte_fifo.sv rtl/spi_flash_reader.sv
    sim/models/flash_sck_startup_sim.sv rtl/jtag_engine.sv
    rtl/jbin_decoder.sv rtl/debounce.sv rtl/uart_tx_status.sv
    rtl/top_ctrl.sv rtl/top.sv
    sim/models/spi_flash_model.sv sim/models/tap_model.sv
    sim/tb_spi_flash_reader.sv sim/tb_jtag_engine.sv
    sim/tb_jbin_decoder.sv sim/tb_top.sv
}

set srcs {}
foreach f $rtl { lappend srcs [file join $root $f] }
if {$fifo_xpm} {
    set xpm [file join $::env(XILINX_VIVADO) data ip xpm]
    lappend srcs [file join $xpm xpm_cdc hdl xpm_cdc.sv] \
                 [file join $xpm xpm_memory hdl xpm_memory.sv] \
                 [file join $xpm xpm_fifo hdl xpm_fifo.sv]
}
set glbl [file join $::env(XILINX_VIVADO) data verilog src glbl.v]

# name, top, generics, list of plusarg lists
set tests {
    {tb_spi_flash_reader            tb_spi_flash_reader {}              {{}}}
    {tb_spi_flash_reader_slow_flash tb_spi_flash_reader {T_V_NS=24.0}   {{}}}
    {tb_jtag_engine                 tb_jtag_engine      {}              {{}}}
    {tb_jbin_decoder                tb_jbin_decoder     {}              {{}}}
    {tb_top                         tb_top              {}              {
        {SCEN=0} {SCEN=1} {SCEN=2} {SCEN=3} {SCEN=4}
        {SCEN=5} {SCEN=6} {SCEN=7} {SCEN=8} {SCEN=9}}}
}

cd $work
puts "xvlog: compiling [llength $srcs] files (XPM FIFO: $fifo_xpm)"
exec xvlog -sv {*}$srcs >& xvlog.log
exec xvlog $glbl >>& xvlog.log

set pass 0
set fail 0
foreach t $tests {
    lassign $t name top generics runs
    if {$filter ne "" && [string first $filter $name] < 0} { continue }
    set gen [list -generic_top "FIFO_XPM=$fifo_xpm"]
    if {$top eq "tb_jtag_engine"} { set gen {} }
    foreach g $generics { lappend gen -generic_top $g }
    exec xelab -debug off -timescale 1ns/1ps {*}$gen -s $name \
        work.$top work.glbl >& xelab_$name.log
    foreach plus $runs {
        set label [string trim "$name $plus"]
        set args [list -testplusarg "VEC=$vec_dir"]
        foreach p $plus { lappend args -testplusarg $p }
        set log [file join $work "[string map {{ } _ = _} $label].log"]
        catch {exec xsim $name -R {*}$args >& $log}
        set fh [open $log r]
        set out [read $fh]
        close $fh
        if {[string first "TEST PASSED" $out] >= 0 &&
            [string first "TEST FAILED" $out] < 0} {
            puts [format "%-45s PASS" $label]
            incr pass
        } else {
            puts [format "%-45s FAIL (see %s)" $label $log]
            incr fail
        }
    }
}
puts "$pass of [expr {$pass + $fail}] passed"
cd $root
if {$fail > 0} { exit 1 }
