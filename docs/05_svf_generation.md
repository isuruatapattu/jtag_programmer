# 05 SVF Generation

The player does not read a bitstream. It plays an SVF that already contains the JTAG operations for one configuration. The file checked in with both applications is `assets/nexys_a7_01.svf`.

## What the checked-in file contains

The header is a single-device Artix-7 configuration sequence:

```svf
TRST OFF;
ENDIR IDLE;
ENDDR IDLE;
STATE RESET;
STATE IDLE;
FREQUENCY 1.00E+07 HZ;
HIR 0 ;
TIR 0 ;
HDR 0 ;
TDR 0 ;
// config/idcode
SIR 6 TDI (09) ;
SDR 32 TDI (00000000) TDO (03631093) MASK (0fffffff) ;
// config/jprog
SIR 6 TDI (0b) ;
SIR 6 TDI (14) ;
RUNTEST 1E-1 SEC;
RUNTEST 10000 TCK;
SIR 6 TDI (14) TDO (11) MASK (31) ;
// config/slr
SIR 6 TDI (05) ;
SDR 30606304 TDI ( ... ) ;
```

Later comments mark `config/start` and `config/status`: a `JSTART` (`SIR 6 TDI (0c)`), a second IDCODE-instruction check, and a status shift whose mask is `0x08000000`. Those comments are the ones Vivado writes when it records a program operation into an SVF target.

`SIR 6 TDI (09)` is the 7-series IDCODE instruction. `0x03631093` is the XC7A100T IDCODE, with the version nibble masked off. `SIR 6 TDI (0b)` is JPROGRAM. The 30,606,304-bit `SDR` is the configuration payload (3,825,788 bytes of shift data, stored as ASCII hex, which is why the file is about 7.7 MB).

`HIR`/`TIR`/`HDR`/`TDR` are all zero. The target chain must be the Artix-7 alone. J10 on the Nexys A7 is that chain. A pod, an FTDI device, or a second FPGA inserted into the scan path will fail the IDCODE check even when the wiring of TCK and TMS is correct.

## Regenerate from a bitstream

Build the design that should end up in the target Nexys A7, and write its bitstream. Then record a program operation against an SVF target. No cable and no board are required for this step. The part must be the Nexys A7-100T device, `xc7a100tcsg324-1`.

In Vivado Tcl:

```tcl
open_hw_manager
connect_hw_server -url localhost:3121
create_hw_target nexys_a7_svf
open_hw_target [lindex [get_hw_targets -regexp .*/nexys_a7_svf] 0]
set dev [create_hw_device -part xc7a100tcsg324-1]
set_property PROGRAM.FILE {C:/path/to/target_design.bit} $dev
program_hw_devices $dev
write_hw_svf {C:/path/to/nexys_a7_01.svf}
close_hw_target
```

The same sequence exists in Hardware Manager: add an SVF target, add the `xc7a100tcsg324-1` device, assign the bitstream, program the device, and write the SVF.

Check the new file before embedding it:

- The first IDCODE `TDO` is `(03631093)` with mask `(0fffffff)`.
- `HIR`, `TIR`, `HDR`, and `TDR` are 0.
- A configuration `SDR` of tens of millions of bits is present.
- The file ends with the startup and status commands, not with a truncated shift.
- No `RUNTEST` value has a decimal point. Vivado writes the init delay as `RUNTEST 0.100000 SEC;`, and the bundled libxsvf rejects that with `SVF Syntax Error` right after the IDCODE check. Rewrite it as `RUNTEST 1E-1 SEC;`, which is the same 0.1 s.

## Install it in the applications

Replace both copies, or the two programmers will embed different payloads:

```text
sw/nexys_a7/app_mb_svf_player/assets/nexys_a7_01.svf
sw/nexys_a7/app_mb_jtag_verifier/assets/nexys_a7_01.svf
sw/zcu102/app_svf_player/assets/nexys_a7_01.svf
```

Rebuild the application. CMake regenerates `svf_blob.generated.S` from `svf_blob.S` and the assembler includes the file with `.incbin`. There is no runtime download of the SVF.

On the Nexys A7 player, add the MicroBlaze tools to `PATH` so the link step can run `mb-size`. The path used with the 2025.2 tools is:

```powershell
$env:Path = 'C:\AMDDesignTools\2025.2\Vitis\gnu\microblaze\nt\bin;' + $env:Path
cmake --build build
```

Run that from `sw/nexys_a7/app_mb_svf_player`, after the Vitis CMake build directory exists.

A full link prints a `text` size a little larger than the SVF, because the file is linked into `.rodata`, and a `bss` size above 32 MiB, because the heap is reserved there. The recorded Nexys A7 link line for this SVF is:

```text
text    data      bss      dec      hex filename
7747420    1624 33571276 41320320 2767f80 app_mb_svf_player.elf
```

At startup the player prints the blob address and size. For this asset the size is 7,682,571 bytes, or 7,712,737 bytes if the checkout converted it to CRLF line endings. A different size means a different file was embedded, or the link did not pick up the regenerated assembly.
