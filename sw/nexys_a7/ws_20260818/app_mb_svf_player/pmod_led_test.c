#include "platform.h"
#include "xparameters.h"
#include "xil_printf.h"
#include "sleep.h"
#include "xgpio.h"
#include "xstatus.h"

#define JA_GPIO_BASEADDR XPAR_XGPIO_0_BASEADDR
#define JA_OUT_CHANNEL 1
#define JA_OUT_MASK 0x0000000F
#define JA_TEST_DELAY_US 300000

/* GPIO JA-Pmod test */
static int init_ja_gpio(XGpio *Gpio)
{
    XGpio_Config *CfgPtr;

    CfgPtr = XGpio_LookupConfig(JA_GPIO_BASEADDR);
    if (CfgPtr == NULL) {
        return XST_FAILURE;
    }

    return XGpio_CfgInitialize(Gpio, CfgPtr, CfgPtr->BaseAddress);
}

static void test_ja_outputs(XGpio *Gpio)
{
    static const u32 ja_pattern[] = {
        0x1,
        0x2,
        0x4,
        0x8,
        0xF,
        0x0
    };
    int i;

    for (i = 0; i < (int)(sizeof(ja_pattern) / sizeof(ja_pattern[0])); i++) {
        XGpio_DiscreteWrite(Gpio, JA_OUT_CHANNEL, ja_pattern[i] & JA_OUT_MASK);
        usleep(JA_TEST_DELAY_US);
    }
}

int main()
{
    int status;
    XGpio JaGpio;

    init_platform();

    status = init_ja_gpio(&JaGpio);
    if (status != XST_SUCCESS) {
        xil_printf("JA GPIO init failed\r\n");
        while (1);
    }

    XGpio_SetDataDirection(&JaGpio, JA_OUT_CHANNEL, 0x00000000);
    XGpio_DiscreteWrite(&JaGpio, JA_OUT_CHANNEL, 0x00000000);

    xil_printf("JA GPIO output test ready.\r\n");
    xil_printf("Cycling JA output pins.\r\n");

    while (1) {
        test_ja_outputs(&JaGpio);
    }
}
