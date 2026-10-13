ZCU102 J55 input test (standalone Cortex-A53, platform)

Hardware export path: hw/zcu102_jtag_programmer/design_2_wrapper.xsa
Replace this export with the rebuilt all-input hardware and update/rebuild
the Vitis platform before running. The old JTAG bitstream has channel 1
hardwired as outputs; software direction writes cannot turn those into inputs.

Required Vivado configuration: dual-channel AXI GPIO, four bits per channel,
both channels All Inputs. Connect both external buses to gpio_io_i[3:0] and
gpio2_io_i[3:0], preserving the bit-to-package-pin assignments below. Update
the HDL wrapper and constraints if you rename the former jtag_out bus.

Build input_test in Vitis and run with its existing hardware launch configuration.
Use the new all-input bitstream and the BSP UART console at 115200 baud, 8N1.
Make sure the launch configuration programs that new bitstream.

AXI GPIO channel 1 inputs (former jtag_out bus in jtag_pins.xdc):
  Bit 0 / 0x01: J55.1, FPGA A20
  Bit 1 / 0x02: J55.3, FPGA B20
  Bit 2 / 0x04: J55.5, FPGA A22
  Bit 3 / 0x08: J55.2, FPGA B21

AXI GPIO channel 2 inputs from jtag_pins.xdc:
  Bit 0 / 0x01: J55.7, FPGA A21
  Bit 1 / 0x02: J55.4, FPGA C21
  Bit 2 / 0x04: J55.6, FPGA C22
  Bit 3 / 0x08: J55.8, FPGA D21

When any input is high, print "Input detected:" and all high pin names.
Wait three seconds before reading the inputs again. A pin held high repeats
the message every three seconds. Pulses during the pause are not captured.

Diagnostic v2 prints both unmasked channel values on the first read and
whenever either changes. If all eight pins are high, both values should be
0x0000000F. If output stops at "Reading GPIO channels 1 and 2..." with no raw
values, a GPIO read has not completed; check PL programming, AXI clock/reset
and launch initialization. Zero means that channel's read returned all low.

For testing, keep unused inputs at a defined low level (for example, with
external pull-down resistors). Apply a 3.3 V logic signal with common ground
to each input in turn. Floating inputs can cause unwanted detections.
Do not connect 3.3 V to the former output pins while the old bitstream is loaded.
