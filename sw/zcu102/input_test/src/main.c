#include "xparameters.h"
#include "xgpio.h"
#include "xil_printf.h"
#include "xstatus.h"
#include "sleep.h"

#define INPUT_MASK 0x0FU

int main(void)
{
    XGpio gpio;
    u32 inputs1;
    u32 inputs2;
    u32 raw1;
    u32 raw2;
    u32 previous_raw1 = 0U;
    u32 previous_raw2 = 0U;
    int first_read = 1;

    xil_printf("ZCU102 input test - all 8 pins, diagnostic v2\r\n");

    if (XGpio_Initialize(&gpio, XPAR_XGPIO_0_BASEADDR) != XST_SUCCESS) {
        xil_printf("GPIO initialization failed\r\n");
        return XST_FAILURE;
    }

    /* Requires both four-bit AXI GPIO channels wired as inputs in Vivado. */
    XGpio_SetDataDirection(&gpio, 1U, INPUT_MASK);
    XGpio_SetDataDirection(&gpio, 2U, INPUT_MASK);

    xil_printf("ZCU102: waiting for input on J55.1 through J55.8\r\n");
    xil_printf("Reading GPIO channels 1 and 2...\r\n");

    while (1) {
        raw1 = XGpio_DiscreteRead(&gpio, 1U);
        raw2 = XGpio_DiscreteRead(&gpio, 2U);
        if (first_read || (raw1 != previous_raw1) || (raw2 != previous_raw2)) {
            xil_printf("GPIO1 raw=0x%08x GPIO2 raw=0x%08x\r\n", raw1, raw2);
            previous_raw1 = raw1;
            previous_raw2 = raw2;
            first_read = 0;
        }
        inputs1 = raw1 & INPUT_MASK;
        inputs2 = raw2 & INPUT_MASK;

        if ((inputs1 != 0U) || (inputs2 != 0U)) {
            xil_printf("Input detected:");
            /* Preserve the pin/bit assignments from jtag_pins.xdc. */
            if (inputs1 & 0x01U) xil_printf(" J55.1");
            if (inputs1 & 0x08U) xil_printf(" J55.2");
            if (inputs1 & 0x02U) xil_printf(" J55.3");
            if (inputs2 & 0x02U) xil_printf(" J55.4");
            if (inputs1 & 0x04U) xil_printf(" J55.5");
            if (inputs2 & 0x04U) xil_printf(" J55.6");
            if (inputs2 & 0x01U) xil_printf(" J55.7");
            if (inputs2 & 0x08U) xil_printf(" J55.8");
            xil_printf("\r\n");

            sleep(3);
        }
    }
}
