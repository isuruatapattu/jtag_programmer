# 02 Hardware Setup

Use two boards. The programmer runs the SVF player. The target is the Nexys A7 whose Artix-7 will be configured. Programming the same FPGA that is running the player replaces the player and stops the transfer.

Wiring is shown in [wiring_diagram.png](images/wiring_diagram.png).

## Programmer: Nexys A7, Pmod JA

JA is the 12-pin Pmod. Pins 1–4 and 7–10 are the AXI GPIO signals. Pins 5 and 11 are ground. Pins 6 and 12 are 3.3 V.

| JA pin | FPGA pin | Port | GPIO | JTAG | Direction |
|---|---|---|---|---|---|
| JA1 | C17 | `ck_a0[0]` | channel 1, bit 0 | TCK | output |
| JA2 | D18 | `ck_a0[1]` | channel 1, bit 1 | TMS | output |
| JA3 | E18 | `ck_a0[2]` | channel 1, bit 2 | TDI | output |
| JA4 | G17 | `ck_a0[3]` | channel 1, bit 3 | unused | output |
| JA7 | D17 | `ck_b0[0]` | channel 2, bit 0 | TDO | input |
| JA8 | E17 | `ck_b0[1]` | channel 2, bit 1 | unused | input |
| JA9 | F18 | `ck_b0[2]` | channel 2, bit 2 | unused | input |
| JA10 | G18 | `ck_b0[3]` | channel 2, bit 3 | unused | input |

Constraints are the board master XDC:

`hw/nexys_a7_jtag_programmer/nexys_a7_jtag_programmer.srcs/constrs_1/imports/resources/Nexys-A7-100T-Master.xdc`

Console: the shared UART/JTAG USB port (J6, labeled PROG) through the AXI UART Lite `usb_uart` interface. Match the terminal to the baud rate on that IP. The Nexys A7 board preset is 9600 8N1 unless the IP was edited.

Power the programmer normally and program it from Vivado or Vitis over J6. That USB-JTAG path belongs to the programmer only.

## Programmer: ZCU102, Pmod J55

`hw/zcu102_jtag_programmer/zcu102_jtag_programmer.srcs/constrs_1/new/jtag_pins.xdc` places the same 4-bit output and 4-bit input buses on J55, all LVCMOS33.

| J55 pin | FPGA pin | Port | JTAG | Direction |
|---|---|---|---|---|
| J55.1 | A20 | `jtag_out[0]` | TCK | output |
| J55.3 | B20 | `jtag_out[1]` | TMS | output |
| J55.5 | A22 | `jtag_out[2]` | TDI | output |
| J55.2 | B21 | `jtag_out[3]` | unused | output |
| J55.7 | A21 | `jtag_in[0]` | TDO | input |
| J55.4 | C21 | `jtag_in[1]` | unused | input |
| J55.6 | C22 | `jtag_in[2]` | unused | input |
| J55.8 | D21 | `jtag_in[3]` | unused | input |

Use a ground pin on J55 for the return. Do not tie a J55 3.3 V pin to the target.

The application is `app_svf_player` on `standalone_psu_cortexa53_0`. The PS UART is 115200 baud (`platform.c` notes that the boot ROM / BSP sets that rate). The menu text still says `JA1=TCK` and `MicroBlaze SVF player ready`; read those lines as the J55 mapping above.

## Target: second Nexys A7, header J10

The Digilent reference manual calls J10 the JTAG port for an optional external cable (board callout 16). A `.bit` file can be sent either through the onboard USB-JTAG circuit on J6 or through an external master on J10. This project is that external master.

J10 is a single-device TAP: the SVF was generated with no extra header or trailer bits. Connect only these signals:

```text
Programmer TCK  ->  target J10 TCK
Programmer TMS  ->  target J10 TMS
Programmer TDI  ->  target J10 TDI
Programmer TDO  <-  target J10 TDO
Programmer GND <->  target J10 GND
```

Leave the J10 VREF pin on the target. The programmer must not source or load that pin.

Match the silk-screen pin numbers on J10 to the Digilent programming-cable order (TMS, TDI, TDO, TCK, GND, VREF). Confirm the pin-1 mark before connecting. A swapped TDI/TDO pair fails the first IDCODE check.

### Power and the onboard USB-JTAG circuit

J6 and J10 reach the same FPGA TAP. Two masters on TCK, TMS, and TDI will contend.

1. Set JP3 for the barrel jack and power the target from an external supply.
2. Leave the target PROG USB cable unplugged for the whole SVF run.
3. Set the mode jumper JP1 to JTAG. Configuration from JTAG works with JP1 in another position, but the JTAG position stops QSPI, microSD, or USB from loading a different bitstream after the SVF finishes.
4. Turn the target on before starting command `p`.

The DONE LED (callout 6) lights after a successful JTAG configuration. PROG clears the configuration memory.

## LED check with no target

Before wiring J10, the output pins can drive LEDs. Use one resistor per LED, 330 Ω to 1 kΩ, from the pin to the LED anode, cathode to ground.

```text
JA1 (or J55.1) -> resistor -> LED -> GND    TCK
JA2 (or J55.3) -> resistor -> LED -> GND    TMS
JA3 (or J55.5) -> resistor -> LED -> GND    TDI
JA4 (or J55.2) -> resistor -> LED -> GND    pattern test only
```

Do not put an LED on TDO. That pin is an input. Do not leave LEDs attached to TCK, TMS, or TDI once a real target is connected.
