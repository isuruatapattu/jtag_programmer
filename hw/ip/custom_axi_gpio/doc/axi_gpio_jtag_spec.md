# axi_gpio_jtag - custom AXI4-Lite GPIO for the Nexys A7 JTAG port

`axi_gpio_jtag` replaces the Xilinx `axi_gpio_0` instance in
`hw/nexys_a7_jtag_programmer_custom_gpio`. It drives the JA Pmod JTAG pins from
the MicroBlaze. This document is the single source of truth: the reference
model (`tools/gpio_reg_model.py`), the testbench (`sim/tb_axi_gpio_jtag.sv`) and
the RTL (`rtl/*.v`) all implement it, and `traceability.md` maps every
requirement to its check.

The words **must**, **must not** and **may** are normative. Text marked
*Informative* explains context and is not tested.

## 1. Scope and baseline

*Informative.* The design copies the observable behaviour that firmware relies
on in the Xilinx AXI GPIO 2.0 configured as in
`hw/nexys_a7_jtag_programmer/.../design_1_axi_gpio_0_0.xci`:

| Xilinx parameter | Value |
|---|---|
| `C_IS_DUAL` | 1 |
| `C_GPIO_WIDTH`, `C_GPIO2_WIDTH` | 4 |
| `C_ALL_OUTPUTS` (channel 1) | 1 |
| `C_ALL_INPUTS_2` (channel 2) | 1 |
| `C_DOUT_DEFAULT` | `0x00000000` |
| `C_TRI_DEFAULT_2` | `0xFFFFFFFF` |
| `C_INTERRUPT_PRESENT` | 0 |
| `C_S_AXI_ADDR_WIDTH`, `C_S_AXI_DATA_WIDTH` | 9, 32 |

Not in scope: interrupts (`GIER`, `IP IER`, `IP ISR`), bidirectional pins,
widths other than 4, AXI4 bursts, and byte-exact equality with Xilinx read
values for registers that the firmware never reads (`TRI`, `TRI2`).

## 2. Parameters

| ID | Requirement |
|---|---|
| GPIO-PAR-001 | The top module must be named `axi_gpio_jtag`. |
| GPIO-PAR-002 | `GPIO_WIDTH` (channel 1) and `GPIO2_WIDTH` (channel 2) are fixed at 4. They may be Verilog parameters, but only the value 4 is supported and verified. |
| GPIO-PAR-003 | The AXI address width is 9 bits and the data width is 32 bits. |

## 3. Ports

| ID | Port | Dir | Width | Description |
|---|---|---|---|---|
| GPIO-IF-001 | `s_axi_aclk` | in | 1 | Single clock for all logic. 100 MHz in the Nexys design. |
| GPIO-IF-002 | `s_axi_aresetn` | in | 1 | Synchronous active-low reset (section 7). |
| GPIO-IF-003 | `s_axi_awaddr` | in | 9 | Write address. |
| | `s_axi_awvalid` | in | 1 | |
| | `s_axi_awready` | out | 1 | |
| | `s_axi_wdata` | in | 32 | |
| | `s_axi_wstrb` | in | 4 | |
| | `s_axi_wvalid` | in | 1 | |
| | `s_axi_wready` | out | 1 | |
| | `s_axi_bresp` | out | 2 | |
| | `s_axi_bvalid` | out | 1 | |
| | `s_axi_bready` | in | 1 | |
| | `s_axi_araddr` | in | 9 | Read address. |
| | `s_axi_arvalid` | in | 1 | |
| | `s_axi_arready` | out | 1 | |
| | `s_axi_rdata` | out | 32 | |
| | `s_axi_rresp` | out | 2 | |
| | `s_axi_rvalid` | out | 1 | |
| | `s_axi_rready` | in | 1 | |
| GPIO-IF-004 | `gpio_io_o` | out | 4 | Channel 1 outputs. Bit 0 TCK (JA1), bit 1 TMS (JA2), bit 2 TDI (JA3), bit 3 spare (JA4). |
| GPIO-IF-005 | `gpio2_io_i` | in | 4 | Channel 2 inputs, asynchronous to `s_axi_aclk`. Bit 0 TDO (JA7), bits 1..3 spare (JA8..JA10). |

| ID | Requirement |
|---|---|
| GPIO-IF-006 | The module must have exactly the ports listed above, with those names, directions and widths. It must not have `awprot`, `arprot`, `gpio_io_i`, `gpio_io_t`, `gpio2_io_o`, `gpio2_io_t` or `ip2intc_irpt`. |
| GPIO-IF-007 | The AXI ports must be grouped as interface `S_AXI` of type `xilinx.com:interface:aximm:1.0`, using `X_INTERFACE_INFO` attributes, with `PROTOCOL AXI4LITE`, `ADDR_WIDTH 9` and `DATA_WIDTH 32`. `s_axi_aclk` must carry `ASSOCIATED_BUSIF S_AXI` and `ASSOCIATED_RESET s_axi_aresetn`. `s_axi_aresetn` must carry `POLARITY ACTIVE_LOW`. |
| GPIO-IF-008 | The top-level file must be Verilog-2001, not SystemVerilog, so that Vivado IP Integrator can add it as a module reference. |

## 4. Address decode

| ID | Requirement |
|---|---|
| GPIO-ADR-001 | The register index is `addr[8:2]`. `addr[1:0]` must be ignored, so an access with any byte offset acts on the 32-bit word that contains it. |
| GPIO-ADR-002 | Offsets `0x000`, `0x004`, `0x008` and `0x00C` are the registers in section 5. Every other offset in `0x010..0x1FC` is unmapped. |
| GPIO-ADR-003 | A read of an unmapped offset must return `0x00000000` with `RRESP = OKAY`. |
| GPIO-ADR-004 | A write to an unmapped offset must not change any register or output, and must complete with `BRESP = OKAY`. |

*Informative.* The processor reaches this slave at base `0x40000000`. The
address port is 9 bits, so a module reference in the Address Editor gets a 4K
segment and that range cannot be raised. The Xilinx `axi_gpio` IP showed 64K
because its packaged address block is 64K, not because its port is wider. The
interconnect passes the low 9 bits, so the 512-byte register window repeats
every `0x200` bytes inside the segment.

## 5. Register map

All registers are 32 bits. Only bits `[3:0]` hold state. Bits `[31:4]` always
read as 0 and ignore writes.

| Offset | Name | Access | Reset | Driver name |
|---|---|---|---|---|
| `0x000` | `DATA` | R/W | `0x0` | `XGPIO_DATA_OFFSET` |
| `0x004` | `TRI` | R/W | `0x0` | `XGPIO_TRI_OFFSET` |
| `0x008` | `DATA2` | RO | n/a | `XGPIO_DATA2_OFFSET` |
| `0x00C` | `TRI2` | R/W | `0xF` | `XGPIO_TRI2_OFFSET` |

| ID | Requirement |
|---|---|
| GPIO-REG-001 | `DATA` write: the channel 1 output register becomes `wdata[3:0]`. |
| GPIO-REG-002 | `DATA` read: returns `{28'b0, output_register}`. It returns the stored output value, not the pin level. |
| GPIO-REG-003 | `gpio_io_o` must always equal the channel 1 output register. |
| GPIO-REG-004 | `TRI` write: stores `wdata[3:0]`. `TRI` read: returns `{28'b0, stored value}`. `TRI` must not affect `gpio_io_o`, because channel 1 is always an output. |
| GPIO-REG-005 | `DATA2` read: returns `{28'b0, gpio2_sync}`, where `gpio2_sync` is the synchronized `gpio2_io_i` (section 8). |
| GPIO-REG-006 | `DATA2` write: has no effect, and completes with `BRESP = OKAY`. |
| GPIO-REG-007 | `TRI2` write: stores `wdata[3:0]`. `TRI2` read: returns `{28'b0, stored value}`. `TRI2` must not affect how `gpio2_io_i` is sampled, because channel 2 is always an input. |
| GPIO-REG-008 | Bits `[31:4]` of every register must read as 0, regardless of what was written. |

*Informative.* The firmware writes `TRI = 0` and `TRI2 = 0xFFFFFFFF`. The
values are stored so that a read-back is predictable, but they do not change any
pin.

## 6. Write strobes

| ID | Requirement |
|---|---|
| GPIO-STB-001 | A register changes only if `wstrb[0] = 1`. If `wstrb[0] = 0` the write must not change any register, and it still completes with `BRESP = OKAY`. |
| GPIO-STB-002 | `wstrb[3:1]` must be ignored, because no state bits exist in bytes 1..3. |

## 7. AXI4-Lite protocol

The terms *handshake*, *VALID* and *READY* have their AXI meaning: a transfer
happens on a rising clock edge where both VALID and READY are 1.

### 7.1 Write channel

| ID | Requirement |
|---|---|
| GPIO-AXI-001 | The slave must accept the AW and W handshakes in either order, or both in the same cycle. |
| GPIO-AXI-002 | A register write happens only after both the AW and W handshakes of that transaction have occurred. It uses the address from AW and the data and strobe from W. |
| GPIO-AXI-003 | Each write must produce exactly one B response, with `BRESP = 2'b00` (OKAY). |
| GPIO-AXI-004 | When `bvalid = 1`, it must stay 1, with `bresp` stable, until the B handshake. |
| GPIO-AXI-005 | The slave holds at most one write in flight. It must not accept a new AW or W until the B handshake of the current write is complete. |
| GPIO-AXI-006 | When idle and out of reset, with no write in flight, `awready` must be 1 within 2 cycles after `awvalid` rises, and the same holds for `wready` after `wvalid`. |
| GPIO-AXI-007 | `bvalid` must rise within 2 cycles after the later of the AW and W handshakes. |
| GPIO-AXI-008 | The register write, and the resulting `gpio_io_o` change for a `DATA` write, must be visible no later than the first cycle in which `bvalid = 1` for that write. |

### 7.2 Read channel

| ID | Requirement |
|---|---|
| GPIO-AXI-010 | Each AR handshake must produce exactly one R response, with `RRESP = 2'b00` (OKAY). |
| GPIO-AXI-011 | When `rvalid = 1`, it must stay 1, with `rdata` and `rresp` stable, until the R handshake. |
| GPIO-AXI-012 | The slave holds at most one read in flight. It must not accept a new AR until the R handshake of the current read is complete. |
| GPIO-AXI-013 | When idle and out of reset, `arready` must be 1 within 2 cycles after `arvalid` rises. |
| GPIO-AXI-014 | `rvalid` must rise within 2 cycles after the AR handshake. |
| GPIO-AXI-015 | `rdata` is captured when `rvalid` rises. It must reflect every write whose B handshake finished before the AR handshake. |

### 7.3 General

| ID | Requirement |
|---|---|
| GPIO-AXI-020 | A slave output VALID (`bvalid`, `rvalid`) must not depend combinationally on the master's READY input of the same channel. |
| GPIO-AXI-021 | The read and write channels are independent. A read and a write may be in flight at the same time. If a read and a write to the same register overlap (the AR handshake happens before the B handshake of the write), the read may return either the old or the new value. |
| GPIO-AXI-022 | `bresp` and `rresp` must never be `SLVERR` or `DECERR`. |

*Informative.* MicroBlaze issues single 32-bit transfers with `wstrb = 0xF`
through `Xil_Out32` / `Xil_In32` and waits for each to finish.

## 8. Input synchronization

| ID | Requirement |
|---|---|
| GPIO-SYN-001 | `gpio2_io_i` must pass through a 2-stage flip-flop synchronizer clocked by `s_axi_aclk` before reaching the read path. Both stages must have the attribute `(* ASYNC_REG = "TRUE" *)`. |
| GPIO-SYN-002 | If `gpio2_io_i` has held the same value for at least 3 consecutive rising edges of `s_axi_aclk` before the AR handshake edge of a `DATA2` read, and does not change until `rvalid` rises, the read must return that value. |
| GPIO-SYN-003 | No combinational path is allowed from `gpio2_io_i` to any output port. |

## 9. Reset

| ID | Requirement |
|---|---|
| GPIO-RST-001 | `s_axi_aresetn` is sampled on the rising edge of `s_axi_aclk`. Reset is active when it is 0. |
| GPIO-RST-002 | While reset is active, `awready`, `wready`, `bvalid`, `arready` and `rvalid` must be 0, by the first rising edge after reset is sampled at the latest. |
| GPIO-RST-003 | Reset must set `DATA = 0x0`, `TRI = 0x0`, `TRI2 = 0xF`, and `gpio_io_o = 4'b0000`. The JTAG pins then idle at TCK = TMS = TDI = 0. |
| GPIO-RST-004 | Reset in the middle of a transaction must drop that transaction without a response. The register must hold either its value from before the transaction or its reset value, never a partial value. |
| GPIO-RST-005 | After reset deasserts, the next transaction must behave as specified with no extra setup. |
| GPIO-RST-006 | The synchronizer flip-flops do not need to be reset. |

*Informative.* Per the AXI specification, the master keeps VALID low during
reset and in the first cycle after it.

## 10. Timing and implementation

| ID | Requirement |
|---|---|
| GPIO-TIM-001 | `gpio_io_o` must be driven directly by flip-flops, with no logic between the flip-flop and the port. |
| GPIO-TIM-002 | All logic uses `s_axi_aclk` only. Clock gating and generated clocks are not allowed. |
| GPIO-TIM-003 | The design must meet timing at 100 MHz on the XC7A100T-1 with no added constraints. |
| GPIO-TIM-004 | No latches may be inferred, and no vendor primitives or copied Xilinx IP source may be used. |

## 11. Software scenarios

These are the register sequences used by
`sw/nexys_a7/app_mb_svf_player/svf_player.c`. The new app,
`app_mb_svf_player_custome_gpio`, issues the same accesses through `Xil_Out32`
and `Xil_In32`. Each sequence is a test case. In the table, `W addr data`
is a write with `wstrb = 0xF`, and `R addr` is a read.

| ID | Source function | Sequence | Expected result |
|---|---|---|---|
| GPIO-SW-001 | `configure_ja_gpio` | `W 0x04 0x00000000`, `W 0x0C 0xFFFFFFFF`, `W 0x00 0x00000000` | `gpio_io_o = 0x0`. Read-back gives `TRI = 0x0`, `TRI2 = 0xF`, `DATA = 0x0`. |
| GPIO-SW-002 | `test_ja_outputs` | `W 0x00` with `0x1`, `0x2`, `0x4`, `0x8`, `0xF`, `0x0` | `gpio_io_o` follows each value after each write. |
| GPIO-SW-003 | `svf_write_outputs` + `svf_read_tdo` | `W 0x00 (shadow & 0xF)`, then `R 0x08` | Bits `[3:0]` of the read equal `gpio2_io_i`, held stable per GPIO-SYN-002. Bit 0 is TDO. |
| GPIO-SW-004 | `read_inputs_with_tck` / `print_tdo_levels` | `W 0x00 0x0`, `R 0x08`, `W 0x00 0x1`, `R 0x08`, `W 0x00 0x0` | With `gpio2_io_i[0]` tied to `gpio_io_o[0]` in the testbench (the JA1-to-JA7 jumper), the reads give bit 0 = 0, then 1. |
| GPIO-SW-005 | `mb_svf_pulse_tck` stream | At least 10,000 back-to-back `W 0x00` writes with random `[2:0]`, with a `R 0x08` after some of them | Every write appears on `gpio_io_o` in order. No write is lost, duplicated or reordered. |

## 12. Verification exit criteria

- Every ID in this document appears in `traceability.md`.
- Every ID that is marked as testable there has a passing model check and a
  passing simulation test, in both Questa and VCS (`bash sim/run.sh questa all`
  and `bash sim/run.sh vcs all`; usage is in the header of `sim/run.sh`).
- `GPIO-IF-007`, `GPIO-TIM-003` and `GPIO-TIM-004` are checked in Vivado:
  Validate Design, implementation timing, and the synthesis report.
