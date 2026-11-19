# Run with Vivado -mode batch -source export_svf.tcl -tclargs <switches>.
proc export_svf_usage {} {
    puts {Usage: vivado -mode batch -source hw/svf_projects/scripts/export_svf.tcl -tclargs \
    -bit <design.bit> -out <output.svf> [options]

Options:
  -board <name>     arty-s7-25 (default) or nexys-a7-100t
  -part <part>      Override the board FPGA part for a different target
  -target <name>    Virtual target name (default: export_svf_target)
  -server <url>     Hardware server (default: localhost:3121); reuse if connected
  -help            Show this help

Paths may be absolute or relative to the current working directory.
Quote paths containing spaces. The output is overwritten (-force).
Only a virtual, single-device SVF target is programmed; no physical FPGA
is programmed. Start hw_server before running this script.

Vivado console:
  source {C:/dev/soc/jtag_programmer/hw/svf_projects/scripts/export_svf.tcl}
  export_svf_main -bit {C:/path/design.bit} -out {C:/path/design.svf}}
}

proc export_svf_main {args} {
    array set opts {
        -board arty-s7-25
        -part {}
        -bit {}
        -out {}
        -target export_svf_target
        -server localhost:3121
    }
    if {[llength $args] == 0 || $args eq "-help"} {
        export_svf_usage
        return
    }
    if {[llength $args] % 2} {
        error "Expected switch/value pairs; use -help for usage"
    }
    foreach {key value} $args {
        if {![info exists opts($key)]} {error "Unknown switch: $key"}
        if {$value eq ""} {error "Empty value for $key"}
        set opts($key) $value
    }
    array set parts {
        arty-s7-25 xc7s25csga324-1
        nexys-a7-100t xc7a100tcsg324-1
    }
    if {![info exists parts($opts(-board))]} {
        error "Unknown board: $opts(-board); choose arty-s7-25 or nexys-a7-100t"
    }
    if {$opts(-part) eq ""} {set opts(-part) $parts($opts(-board))}
    foreach key {-bit -out} {
        if {$opts($key) eq ""} {error "Required switch: $key"}
        set opts($key) [file normalize $opts($key)]
    }
    if {![file isfile $opts(-bit)] || ![file readable $opts(-bit)]} {
        error "Bitstream is not a readable file: $opts(-bit)"
    }
    if {![string equal -nocase [file extension $opts(-bit)] .bit]} {
        error "The -bit input must have a .bit extension"
    }
    if {![string equal -nocase [file extension $opts(-out)] .svf]} {
        error "The -out destination must have a .svf extension"
    }
    if {![file isdirectory [file dirname $opts(-out)]]} {
        error "Output directory does not exist: [file dirname $opts(-out)]"
    }
    if {![regexp {^[A-Za-z0-9_-]+$} $opts(-target)]} {
        error "Target name must contain only letters, digits, underscores or hyphens"
    }

    open_hw_manager
    set target {}
    set connected_here 0
    set server {}
    try {
        # SID includes a TCP: prefix, whereas -server may omit it.
        set requested [string tolower $opts(-server)]
        regsub {^tcp:} $requested {} requested
        foreach existing [get_hw_servers -quiet] {
            set address [string tolower [get_property SID $existing]]
            regsub {^tcp:} $address {} address
            if {$address eq $requested} {
                set server $existing
                break
            }
        }
        if {$server eq ""} {
            set server [connect_hw_server -url $opts(-server)]
            set connected_here 1
        }
        current_hw_server $server
        set live [get_hw_targets -quiet -filter {IS_OPENED == TRUE}]
        if {[llength $live]} {close_hw_target $live}

        set target [create_hw_target -svf $opts(-target)]
        if {[llength $target] != 1 || ![get_property IS_SVF $target]} {
            error "Refusing to open a non-SVF target"
        }
        open_hw_target $target
        set dev [create_hw_device -part $opts(-part)]
        set_property PROGRAM.FILE $opts(-bit) $dev
        if {![get_property IS_SVF [current_hw_target]]} {
            error "Refusing to program physical hardware"
        }
        program_hw_devices $dev
        write_hw_svf -force $opts(-out)
        puts "Exported SVF: $opts(-out) (part: $opts(-part))"
    } finally {
        if {$target ne ""} {
            catch {close_hw_target $target}
            # Remove only the virtual target created by this invocation so the
            # same command can be run again from the console.
            catch {delete_hw_target $target}
        }
        if {$connected_here} {catch {disconnect_hw_server $server}}
        # Leave Hardware Manager and pre-existing server connections available
        # to the interactive console (batch Vivado exits on its own).
    }
}

if {[info exists argv]} {export_svf_main {*}$argv}
