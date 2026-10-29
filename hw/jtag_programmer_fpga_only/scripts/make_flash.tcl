# Build the flash image (programmer bitstream + JBIN) and optionally program
# it into the Nexys A7 configuration flash.
#
#   cd hw/jtag_programmer_fpga_only
#   python tools/svf2jbin.py <design>.svf build/target.jbin
#   vivado -mode batch -source scripts/make_flash.tcl -tclargs build/target.jbin
#   vivado -mode batch -source scripts/make_flash.tcl -tclargs build/target.jbin program
#
# Arguments: <jbin> [program] [flash part]
#   flash part defaults to s25fl128sxxxxxx0-spi-x1_x2_x4 (Nexys A7). Confirm
#   it for your board revision; the programmer also prints the JEDEC ID on
#   the UART at power-up.
#
# Layout: top.bit at 0x000000, the JBIN at 0x400000 (rtl/top_ctrl.sv
# DATA_ADDR). Writes build/flash.mcs and checks it with tools/check_mcs.py.

set root [file normalize [file join [file dirname [info script]] ..]]
set out  [file join $root build]

if {[llength $argv] < 1} {
    error "usage: make_flash.tcl <target.jbin> \[program\] \[flash part\]"
}
set jbin    [file normalize [lindex $argv 0]]
set program [expr {[llength $argv] > 1 && [lindex $argv 1] eq "program"}]
set part    [expr {[llength $argv] > 2 ? [lindex $argv 2] :
                   "s25fl128sxxxxxx0-spi-x1_x2_x4"}]

set bit        [file join $out top.bit]
set data_addr  0x00400000
set flash_size [expr {16 * 1024 * 1024}]

foreach f [list $bit $jbin] {
    if {![file exists $f]} { error "missing $f" }
}

# Size checks. The .bit file holds a small header on top of the
# configuration data, so its size is an upper bound.
set bit_size  [file size $bit]
set jbin_size [file size $jbin]
if {$bit_size >= $data_addr} {
    error "top.bit is $bit_size bytes and would overlap the JBIN at 0x400000"
}
if {$data_addr + $jbin_size > $flash_size} {
    error "JBIN of $jbin_size bytes does not fit between 0x400000 and 16 MiB"
}
set fh [open $jbin rb]
set magic [read $fh 4]
close $fh
if {$magic ne "JBIN"} { error "$jbin is not a JBIN file" }
puts "top.bit $bit_size bytes, JBIN $jbin_size bytes"

# write_cfgmem takes raw data files only with a .bin extension.
set data_bin [file join $out flash_data.bin]
file copy -force $jbin $data_bin

set mcs [file join $out flash.mcs]
write_cfgmem -force -format mcs -size 16 -interface SPIx4 \
    -loadbit  "up 0x00000000 $bit" \
    -loaddata "up 0x00400000 $data_bin" \
    -file $mcs

set python [expr {[auto_execok python3] ne "" ? "python3" : "python"}]
puts [exec $python [file join $root tools check_mcs.py] $mcs $jbin]

if {!$program} {
    puts "wrote $mcs (not programmed; add 'program' to write the flash)"
    return
}

open_hw_manager
connect_hw_server
open_hw_target
set dev [lindex [get_hw_devices xc7a100t*] 0]
if {$dev eq ""} { error "no xc7a100t found on the JTAG chain" }
current_hw_device $dev
refresh_hw_device -update_hw_probes false $dev

set cfgmem_part [lindex [get_cfgmem_parts $part] 0]
if {$cfgmem_part eq ""} { error "unknown flash part $part" }
create_hw_cfgmem -hw_device $dev $cfgmem_part
set cfgmem [get_property PROGRAM.HW_CFGMEM $dev]
set_property PROGRAM.FILES          [list $mcs] $cfgmem
set_property PROGRAM.ADDRESS_RANGE  {use_file} $cfgmem
set_property PROGRAM.UNUSED_PIN_TERMINATION {pull-none} $cfgmem
set_property PROGRAM.BLANK_CHECK    0 $cfgmem
set_property PROGRAM.ERASE          1 $cfgmem
set_property PROGRAM.CFG_PROGRAM    1 $cfgmem
set_property PROGRAM.VERIFY         1 $cfgmem
set_property PROGRAM.CHECKSUM       0 $cfgmem

# Load the flash programming helper bitstream, then program and verify.
create_hw_bitstream -hw_device $dev [get_property PROGRAM.HW_CFGMEM_BITFILE $dev]
program_hw_devices $dev
refresh_hw_device $dev
program_hw_cfgmem -hw_cfgmem $cfgmem
puts "flash programmed and verified; press PROG or power-cycle the board"
