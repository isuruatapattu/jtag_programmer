# FPGA-only JTAG programmer diagrams

The design is a linear pipeline. The flash reader fills a FIFO, the decoder turns JBIN bytes into one-clock JTAG work items, and the engine drives the PMOD pins. `top_ctrl` runs each stream twice: first a dry pass that checks the stream with the pins released, then a play pass that drives the target.

## End-to-end flow

```mermaid
flowchart LR
    svf["Target SVF"] --> conv["svf2jbin.py: resolve TAP walks, masks, waits and frequency"]
    conv --> jbin["target.jbin"]
    bit["top.bit"] --> mcs["make_flash.tcl: write_cfgmem"]
    jbin --> mcs
    mcs --> flash["QSPI flash: top.bit at 0x000000, JBIN at 0x400000"]
    flash --> boot["Power-up: FPGA configures from top.bit"]
    boot --> ready["Programmer ready"]
    ready --> check["Pass 1: read whole JBIN, no JTAG activity"]
    check --> ok{"Stream valid?"}
    ok -->|"No"| report["Show error on LEDs and UART"]
    ok -->|"Yes"| play["Pass 2: replay JBIN on JTAG pins"]
    play --> target["Target FPGA receives configuration"]
    target --> result["Show result on LEDs and UART"]
```

## Data and control blocks

```mermaid
flowchart LR
    subgraph flash_side ["Flash access"]
        flash["QSPI flash"] <-->|"CS, DQ0, DQ1, CCLK"| reader["spi_flash_reader"]
        reader -->|"fifo_wr, byte"| fifo["byte_fifo: 4 KiB FWFT"]
        fifo -->|"fifo_room: at least 320 bytes free"| reader
    end

    subgraph execution ["Stream execution"]
        fifo -->|"fifo_dout, fifo_empty"| decoder["jbin_decoder + crc32"]
        decoder -->|"fifo_rd"| fifo
        decoder -->|"work item: TMS, TDI, hold, check, expected TDO, wait"| engine["jtag_engine"]
        engine -->|"ready, idle, err, err_tck"| decoder
    end

    subgraph control ["Control and user I/O"]
        controls["BTNC, BTNU, SW13-SW15, SW2:0"] --> ctrl["top_ctrl"]
        ctrl -->|"stream_en, fifo_rst"| reader
        ctrl -->|"start, dry, abort"| decoder
        decoder -->|"done, status, progress"| ctrl
        ctrl --> leds["LEDs"]
        ctrl --> uart["uart_tx_status"]
    end

    engine -->|"JA1 TCK, JA2 TMS, JA3 TDI"| target["Target JTAG TAP"]
    target -->|"JA7 TDO"| engine
```

## Programming sequence

```mermaid
sequenceDiagram
    actor User
    participant Ctrl as top_ctrl
    participant Reader as spi_flash_reader
    participant FIFO as byte_fifo
    participant Dec as jbin_decoder
    participant Eng as jtag_engine
    participant Target as Target TAP

    Reader->>Reader: Send 8 dummy SCK cycles after EOS
    Reader->>Reader: Read JEDEC ID with 0x9F
    Reader-->>Ctrl: id_done and id_ok
    Ctrl-->>User: UART line FLASH OK and LD0 ready

    User->>Ctrl: Press BTNC
    Ctrl->>FIFO: Reset FIFO
    Ctrl->>Reader: Enable stream at 0x400000
    Ctrl->>Dec: Start pass 1 with dry = 1
    loop Until END or error
        Reader->>FIFO: 256-byte 0x03 reads when room exists
        FIFO->>Dec: Header, opcodes and data bytes
        Dec->>Dec: Check opcode, operands, CRC and TCK count
    end
    Dec-->>Ctrl: Pass 1 OK

    Ctrl->>FIFO: Reset FIFO
    Ctrl->>Reader: Restart stream at 0x400000
    Ctrl->>Eng: Release clear and enable JTAG pins
    Ctrl->>Dec: Start pass 2 with dry = 0
    loop For every JBIN clock
        Dec->>Eng: One work item
        Eng->>Target: Falling edge, TMS and TDI update, rising edge
        Target-->>Eng: TDO for the cycle
        Eng->>Eng: Compare checked TDO bits
    end
    Dec-->>Ctrl: OK, TDO error or another status
    Ctrl-->>User: LEDs and UART result
```

## `top_ctrl` state machine

```mermaid
stateDiagram-v2
    [*] --> T_ID
    T_ID --> T_READY: JEDEC accepted
    T_ID --> T_IDERR: JEDEC rejected
    T_IDERR --> T_IDERR: Wait for reset
    T_READY --> T_SETUP: BTNC or one auto-start
    T_SETUP --> T_READY: Abort during setup
    T_SETUP --> T_RUN: 64-cycle setup complete
    T_RUN --> T_SETUP: Pass 1 OK, start pass 2
    T_RUN --> T_READY: Pass 2 complete
    T_RUN --> T_READY: Error or abort
```

| State | Main actions |
|---|---|
| `T_ID` | Wait for the flash JEDEC result. |
| `T_READY` | Release the JTAG pins, keep the FIFO reset, and wait for a start. |
| `T_SETUP` | Reset the FIFO for 16 cycles, restart the flash stream, and start the decoder. |
| `T_RUN` | Run either the dry pass or the play pass. |
| `T_IDERR` | Remain stopped until reset. |

## `jbin_decoder` state machine

```mermaid
stateDiagram-v2
    [*] --> D_IDLE
    D_IDLE --> D_HDR: start
    D_HDR --> D_HCHK: 32 header bytes received
    D_HCHK --> D_IDLE: Header error
    D_HCHK --> D_OP: Header OK

    D_OP --> D_ARG: Opcode with operands
    D_OP --> D_FIN: END is last byte
    D_OP --> D_DRAIN: Format error in dry pass
    D_OP --> D_RESET: Format error in play pass
    D_ARG --> D_EXEC: Operands complete

    D_EXEC --> D_TMS: TMS
    D_EXEC --> D_SHIFT: TDI-only SHIFT
    D_EXEC --> D_GRP: Compare SHIFT
    D_EXEC --> D_RUN: RUNCLK with count above 0
    D_EXEC --> D_WAITI: Nonzero WAIT_US in play pass
    D_EXEC --> D_SYNC: SET_DIV, TRST or zero count

    D_GRP --> D_GBITS: TDI, TDO and mask loaded
    D_GBITS --> D_GRP: Next group of 8 bits
    D_TMS --> D_SYNC: Last bit issued
    D_SHIFT --> D_SYNC: Last bit issued
    D_GBITS --> D_SYNC: Last bit issued
    D_RUN --> D_SYNC: Last clock issued
    D_WAITI --> D_SYNC: Wait item accepted

    D_SYNC --> D_OP: Engine idle and no error
    D_SYNC --> D_IDLE: Abort in dry pass
    D_SYNC --> D_RESET: TDO error or abort in play pass

    D_DRAIN --> D_IDLE: Payload consumed and CRC checked
    D_FIN --> D_IDLE: CRC and TCK checks complete
    D_FIN --> D_RESET: TDO error
    D_RESET --> D_RDRAIN: 5 TMS=1 clocks issued
    D_RDRAIN --> D_IDLE: Engine idle, status reported
```

Two paths matter most. A TDI-only `SHIFT` takes TDI bits directly from the current FIFO byte, so long shifts continue without per-byte stalls. A compare `SHIFT` loads three bytes for each 8-bit group (TDI, expected TDO, mask), then issues the eight checked clocks.

## `jtag_engine` state machine

```mermaid
stateDiagram-v2
    [*] --> E_IDLE
    E_IDLE --> E_LOW: Clock item accepted
    E_IDLE --> E_WAIT: Wait item accepted
    E_LOW --> E_HIGH: Low half period complete
    E_HIGH --> E_LOW: Next clock accepted at last high cycle
    E_HIGH --> E_WAIT: Wait accepted at last high cycle
    E_HIGH --> E_IDLE: Last high cycle and no item
    E_WAIT --> E_IDLE: Microsecond count complete
    E_WAIT --> E_IDLE: Abort cancels wait
```

```text
TCK      ‾‾‾‾‾\_____________/‾‾‾‾‾‾‾‾‾‾‾‾‾‾\______
TMS/TDI  ======X===========================X=====
TDO      ========X target response for cycle===X
Sample                                        ^ IOB capture before next fall
Compare                                          ^^ two clocks later
```

The engine holds TCK low for `half` system clocks, then high for `half` system clocks. With the 100 MHz clock, `half = 5` gives 10 MHz and `half = 2` gives 25 MHz.

## `spi_flash_reader` state machine

```mermaid
stateDiagram-v2
    [*] --> S_EOS
    S_EOS --> S_DUMMY: STARTUPE2 EOS
    S_DUMMY --> S_GAP: 8 dummy clocks complete
    S_GAP --> S_CSLOW: JEDEC ID not read
    S_GAP --> S_IDLE: JEDEC ID done
    S_IDLE --> S_CSLOW: stream_en and fifo_room
    S_CSLOW --> S_XFER: 2-cycle CS setup
    S_CSLOW --> S_GAP: Stream aborted
    S_XFER --> S_END: Last command or data bit
    S_XFER --> S_GAP: Stream aborted
    S_END --> S_GAP: Complete command
```

```text
One SPI bit = 4 system clocks = 40 ns

Phase    ph0     ph1     ph2     ph3
SCK      0       0       1       1
MOSI     changes at ph0
MISO     flash drives after the SCK fall
Sample   IOB register captures at the start of ph3
```

## Error handling

```mermaid
flowchart TD
    err["Error detected"] --> header{"Header error?"}
    header -->|"Yes"| report_header["Report ERR HDR; JTAG never enabled"]
    header -->|"No"| pass{"Current pass"}
    pass -->|"Dry"| format{"Format error?"}
    format -->|"Yes"| drain["Read the rest of the payload"]
    drain --> crc{"CRC correct?"}
    crc -->|"No"| report_crc["Report ERR CRC"]
    crc -->|"Yes"| report_format["Report format error"]
    format -->|"No"| report_dry["Report dry-pass status"]
    pass -->|"Play"| play_error{"TDO error, abort or format error?"}
    play_error -->|"Yes"| reset_tap["Send 5 TMS=1 clocks"]
    reset_tap --> report_play["Report status"]
    play_error -->|"CRC or TCK at END"| report_end["Report ERR CRC or ERR TCK"]
```
