# QuestaSim script: compile, simulate and run axi_mapped_registers_tb
# Usage (from this sim directory):
#   GUI:    vsim -do run.do
#   Batch:  vsim -c -do "set BATCH 1; do run.do"

# Work from the directory this script lives in, so it can be started from
# any current directory (e.g. "do <path>/run.do" in the transcript).
set SIM_DIR [file dirname [file normalize [info script]]]
if {![file isdirectory $SIM_DIR/../rtl]} {
    set SIM_DIR [pwd]
}
cd $SIM_DIR
set RTL_DIR $SIM_DIR/../rtl

if {[file exists work]} {
    vdel -lib work -all
}
vlib work
vmap work work

# Compile order: leaf modules first, then top, then testbench
vlog -sv -work work -lint \
    $RTL_DIR/axi_write_logic.sv \
    $RTL_DIR/axi_read_logic.sv \
    $RTL_DIR/axi_mapped_registers.sv \
    $RTL_DIR/axi_mapped_registers_tb.sv

if {[info exists BATCH] && $BATCH} {
    vsim -c -voptargs=+acc work.axi_mapped_registers_tb
    run -all
    quit -f
} else {
    vsim -voptargs=+acc work.axi_mapped_registers_tb
    do wave.do
    run -all
    wave zoom full
}
