@echo off
REM Run the testbench in QuestaSim.
REM   run_sim.bat        -> batch mode (console only)
REM   run_sim.bat gui    -> GUI with waveforms
cd /d "%~dp0"
if /I "%1"=="gui" (
    vsim -do run.do
) else (
    vsim -c -do "set BATCH 1; do run.do"
)
