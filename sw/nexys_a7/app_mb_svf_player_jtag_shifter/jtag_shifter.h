#ifndef JTAG_SHIFTER_H
#define JTAG_SHIFTER_H

/*
 * Register interface of hw/ip/jtag_shifter. See
 * hw/ip/jtag_shifter/doc/jtag_shifter_spec.md.
 *
 * The block design adds the IP as a module reference, which does not create
 * an XPAR_ define, so the address assigned in
 * hw/nexys_a7_jtag_programmer_jtag_shifter is repeated here.
 */

#include "xil_io.h"
#include "xil_types.h"

#define JSH_BASEADDR            0x44A00000U

#define JSH_CTRL_OFFSET         0x00U
#define JSH_STATUS_OFFSET       0x04U
#define JSH_CLKDIV_OFFSET       0x08U
#define JSH_CFG_OFFSET          0x0CU
#define JSH_DATA_OFFSET         0x10U
#define JSH_TDO_OFFSET          0x14U
#define JSH_CYCLES_OFFSET       0x18U
#define JSH_ID_OFFSET           0x1CU

#define JSH_CTRL_ENGINE_EN      0x00000001U
#define JSH_CTRL_FLUSH          0x00000002U

#define JSH_STATUS_BUSY         0x00000001U
#define JSH_STATUS_TX_FULL      0x00000002U
#define JSH_STATUS_RX_EMPTY     0x00000004U
#define JSH_STATUS_TX_EMPTY     0x00000008U
#define JSH_STATUS_RX_FULL      0x00000010U

#define JSH_CFG_NBITS_MASK      0x0000001FU
#define JSH_CFG_MODE_TMS        0x00000100U
#define JSH_CFG_TMS_LAST        0x00000200U
#define JSH_CFG_CAPTURE         0x00000400U

#define JSH_ID_VALUE            0x4A534831U
#define JSH_CLKDIV_MAX          0xFFFFU
#define JSH_RX_DEPTH            256U

static inline void jsh_write(u32 offset, u32 value)
{
    Xil_Out32(JSH_BASEADDR + offset, value);
}

static inline u32 jsh_read(u32 offset)
{
    return Xil_In32(JSH_BASEADDR + offset);
}

static inline u32 jsh_cfg(u32 nbits, u32 flags)
{
    return ((nbits - 1U) & JSH_CFG_NBITS_MASK) | flags;
}

static inline void jsh_wait_idle(void)
{
    while ((jsh_read(JSH_STATUS_OFFSET) & JSH_STATUS_BUSY) != 0U) {
    }
}

/* Blocks until a captured word is available. */
static inline u32 jsh_pop_tdo(void)
{
    while ((jsh_read(JSH_STATUS_OFFSET) & JSH_STATUS_RX_EMPTY) != 0U) {
    }
    return jsh_read(JSH_TDO_OFFSET);
}

#endif
