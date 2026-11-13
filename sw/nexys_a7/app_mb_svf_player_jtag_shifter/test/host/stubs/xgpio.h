#pragma once
#include "xgpio_l.h"
typedef struct { UINTPTR BaseAddress; } XGpio_Config;
typedef struct { UINTPTR BaseAddress; } XGpio;
XGpio_Config *XGpio_LookupConfig(UINTPTR b);
int XGpio_CfgInitialize(XGpio *g, XGpio_Config *c, UINTPTR b);
void XGpio_SetDataDirection(XGpio *g, unsigned ch, u32 m);
void XGpio_DiscreteWrite(XGpio *g, unsigned ch, u32 v);
u32 XGpio_DiscreteRead(XGpio *g, unsigned ch);
