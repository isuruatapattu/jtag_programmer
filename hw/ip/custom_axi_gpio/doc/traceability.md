# axi_gpio_jtag traceability

This table maps each requirement in [axi_gpio_jtag_spec.md](axi_gpio_jtag_spec.md)
to the checks that cover it. Rows are added or changed only when the spec
changes. The Status column is updated as checks start to pass.

Column meanings:

- **Model check**: a function in `tools/gpio_reg_model.py`, run by
  `python tools/gpio_reg_model.py`.
- **Sim test**: a task in `sim/tb/tb_axi_gpio_jtag.sv`, run alone with
  `bash sim/run.sh <tool> sim --test <name>` (plusarg `+TEST=<name>`).
  `assert` = an SVA property in `sim/tb/axi_lite_checker.sv`, always on.
  `all` = checked in every test; `all (every write)` = checked by `do_write`
  after every write.
- **RTL**: the module that implements the requirement.
  `top` = `axi_gpio_jtag.v`, `slave` = `axi_lite_slave.v`,
  `regs` = `gpio_jtag_regs.v`.
- **Other**: checks done outside simulation. `review` = code review against
  the spec, `lint` = `bash sim/run.sh <tool> lint` (Questa
  `vlog -vlog01compat -lint`, VCS `+v2k +lint=all`) plus the local slang and
  Yosys checks,
  `vivado` = Validate Design or implementation reports.
- **Status**: `spec` = specified only, `model` = model check passes,
  `sim` = simulation passes, `done` = every listed check passes.

| ID | Summary | Model check | Sim test | RTL | Other | Status |
|---|---|---|---|---|---|---|
| GPIO-PAR-001 | Top named `axi_gpio_jtag` | - | all (instantiation) | top | review | sim |
| GPIO-PAR-002 | Widths fixed at 4 | - | all | top | review | sim |
| GPIO-PAR-003 | Address width 9, data width 32 | - | all | top | review | sim |
| GPIO-IF-001 | Single clock `s_axi_aclk` | - | all | top | review | sim |
| GPIO-IF-002 | `s_axi_aresetn` port | - | `t_reset_values` | top | review | sim |
| GPIO-IF-003 | AXI4-Lite port list | - | all | top | review | sim |
| GPIO-IF-004 | `gpio_io_o[3:0]` port | - | `t_data_rw` | top | review | sim |
| GPIO-IF-005 | `gpio2_io_i[3:0]` port | - | `t_data2_read` | top | review | sim |
| GPIO-IF-006 | No extra ports | - | - | top | review, lint | spec |
| GPIO-IF-007 | `S_AXI` interface attributes | - | - | top | vivado | spec |
| GPIO-IF-008 | Verilog-2001 top file | - | - | top | lint, vivado | spec |
| GPIO-ADR-001 | `addr[1:0]` ignored | `check_addr_low_bits_ignored` | `t_addr_low_bits` | slave, regs | - | sim |
| GPIO-ADR-002 | Four mapped offsets | `check_register_map` | `t_unmapped` | regs | - | sim |
| GPIO-ADR-003 | Unmapped read = 0, OKAY | `check_unmapped_read` | `t_unmapped` | regs | - | sim |
| GPIO-ADR-004 | Unmapped write ignored, OKAY | `check_unmapped_write` | `t_unmapped` | regs | - | sim |
| GPIO-REG-001 | `DATA` write sets output register | `check_data_write` | `t_data_rw` | regs | - | sim |
| GPIO-REG-002 | `DATA` read returns output register | `check_data_read` | `t_data_rw` | regs | - | sim |
| GPIO-REG-003 | `gpio_io_o` = output register | `check_data_write` | `t_data_rw`, all (every write) | regs | - | sim |
| GPIO-REG-004 | `TRI` stored, no pin effect | `check_tri_storage` | `t_tri_rw` | regs | - | sim |
| GPIO-REG-005 | `DATA2` read = synchronized input | `check_data2_read` | `t_data2_read` | regs | - | sim |
| GPIO-REG-006 | `DATA2` write ignored | `check_data2_write_ignored` | `t_data2_read` | regs | - | sim |
| GPIO-REG-007 | `TRI2` stored, no input effect | `check_tri2_storage` | `t_tri_rw` | regs | - | sim |
| GPIO-REG-008 | Bits `[31:4]` read 0 | `check_upper_bits_zero` | `t_upper_bits` | regs | - | sim |
| GPIO-STB-001 | `wstrb[0] = 0` leaves registers unchanged | `check_wstrb0_clear` | `t_wstrb` | regs | - | sim |
| GPIO-STB-002 | `wstrb[3:1]` ignored | `check_wstrb_upper_ignored` | `t_wstrb` | regs | - | sim |
| GPIO-AXI-001 | AW/W in any order | - | `t_aw_w_order` | slave | - | sim |
| GPIO-AXI-002 | Write only after AW and W | - | `t_aw_w_order` | slave | - | sim |
| GPIO-AXI-003 | One B per write, OKAY | - | assert | slave | - | sim |
| GPIO-AXI-004 | `bvalid` held until handshake | - | `t_backpressure`, assert | slave | - | sim |
| GPIO-AXI-005 | One write in flight | - | `t_backpressure`, assert | slave | - | sim |
| GPIO-AXI-006 | `awready`/`wready` within 2 cycles | - | assert | slave | - | sim |
| GPIO-AXI-007 | `bvalid` within 2 cycles | - | assert | slave | - | sim |
| GPIO-AXI-008 | Write visible by first `bvalid` cycle | - | `t_data_rw`, all (every write) | slave, regs | - | sim |
| GPIO-AXI-010 | One R per AR, OKAY | - | assert | slave | - | sim |
| GPIO-AXI-011 | `rvalid`/`rdata` held until handshake | - | `t_backpressure`, assert | slave | - | sim |
| GPIO-AXI-012 | One read in flight | - | `t_backpressure`, assert | slave | - | sim |
| GPIO-AXI-013 | `arready` within 2 cycles | - | assert | slave | - | sim |
| GPIO-AXI-014 | `rvalid` within 2 cycles | - | assert | slave | - | sim |
| GPIO-AXI-015 | Read reflects completed writes | `check_read_after_write` | `t_data_rw`, `t_random` | slave, regs | - | sim |
| GPIO-AXI-020 | VALID not combinational on READY | - | - | slave | review | spec |
| GPIO-AXI-021 | Read and write channels independent | - | `t_concurrent_rw` | slave | - | sim |
| GPIO-AXI-022 | Never SLVERR/DECERR | - | assert | slave | - | sim |
| GPIO-SYN-001 | 2-stage synchronizer with `ASYNC_REG` | `check_sync_latency` | `t_sync_latency` | regs | review | sim |
| GPIO-SYN-002 | Stable input read within 3 cycles | `check_sync_latency` | `t_sync_latency` | regs | - | sim |
| GPIO-SYN-003 | No combinational input-to-output path | - | - | regs, top | review | spec |
| GPIO-RST-001 | Synchronous active-low reset | `check_reset_values` | `t_reset_values` | slave, regs | review | sim |
| GPIO-RST-002 | Handshake outputs 0 in reset | - | `t_reset_values`, assert | slave | - | sim |
| GPIO-RST-003 | Reset register values | `check_reset_values` | `t_reset_values` | regs | - | sim |
| GPIO-RST-004 | Reset mid-transaction drops it cleanly | - | `t_reset_mid_txn` | slave, regs | - | sim |
| GPIO-RST-005 | Normal operation after reset | - | `t_reset_mid_txn` | slave | - | sim |
| GPIO-RST-006 | Synchronizer not reset | - | - | regs | review | spec |
| GPIO-TIM-001 | `gpio_io_o` straight from flip-flops | - | - | regs | review, vivado | spec |
| GPIO-TIM-002 | Single clock domain | - | - | all | review, vivado | spec |
| GPIO-TIM-003 | Timing met at 100 MHz | - | - | all | vivado | spec |
| GPIO-TIM-004 | No latches, primitives or copied IP | - | - | all | lint, vivado | spec |
| GPIO-SW-001 | `configure_ja_gpio` sequence | `check_sw_configure` | `t_sw_configure` | all | - | sim |
| GPIO-SW-002 | `test_ja_outputs` sequence | `check_sw_test_outputs` | `t_sw_test_outputs` | all | - | sim |
| GPIO-SW-003 | Write outputs, read TDO | `check_sw_write_read_tdo` | `t_sw_write_read_tdo` | all | - | sim |
| GPIO-SW-004 | TDO loopback with TCK low, then high | `check_sw_loopback` | `t_sw_loopback` | all | - | sim |
| GPIO-SW-005 | Stream of 10,000 or more writes | `check_sw_stream` | `t_sw_stream` | all | - | sim |

## Coverage summary

- 60 requirements in total.
- 24 have a model check. The rest are protocol, structure or implementation
  rules that the register model cannot observe.
- 50 have a simulation test or an always-on assertion.
- 10 are checked only by review, lint or Vivado: GPIO-IF-006..008,
  GPIO-AXI-020, GPIO-SYN-003, GPIO-RST-006 and GPIO-TIM-001..004.

Questa 2021.3_2 on 12 Nov 2026: lint and compile clean, all 19 tests pass on
seeds 1 to 5 and again with coverage, 17 assertions at 100 percent with no
failures, statement, branch and expression coverage of the RTL at 100 percent,
all 8 mutants killed. The Status column records that run. Toggle coverage was
not collected. VCS has not been run, and the 10 rows above stay at `spec`.
