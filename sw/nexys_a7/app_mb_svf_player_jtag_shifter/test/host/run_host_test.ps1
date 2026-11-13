# Windows version of run_host_test.sh (needs gcc on PATH).
$ErrorActionPreference = "Stop"
$here = $PSScriptRoot
$app = Join-Path $here "..\.."
$x = Join-Path $app "external\libxsvf"
$out = Join-Path $env:TEMP "jsh_host_test.exe"
$src = @("svf.c", "xsvf.c", "tap.c", "statename.c", "memname.c", "play.c", "scan.c") | ForEach-Object { Join-Path $x $_ }
gcc -std=gnu99 -O1 -Wall -Wno-unused-function "-I$here\stubs" "-I$app" "-I$x" (Join-Path $here "host_test.c") @src -o $out
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& $out
exit $LASTEXITCODE
