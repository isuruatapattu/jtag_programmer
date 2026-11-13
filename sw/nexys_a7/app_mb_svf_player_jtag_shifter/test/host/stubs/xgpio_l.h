#pragma once
#include "xil_io.h"
#define XGPIO_DATA_OFFSET 0
#define XGPIO_DATA2_OFFSET 8
#define XGpio_WriteReg(b,o,v) Xil_Out32((b)+(o),(v))
#define XGpio_ReadReg(b,o) Xil_In32((b)+(o))
