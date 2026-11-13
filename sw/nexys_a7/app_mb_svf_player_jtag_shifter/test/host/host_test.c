/* Host model test: real svf_player.c + libxsvf against modelled GPIO,
 * jtag_shifter registers and a TAP. Compares the rising-edge pin trace of
 * the GPIO and shifter paths. */
#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
#include "xil_types.h"

void xil_printf(const char *f, ...);
#define main player_main
#include "svf_player.c"
#undef main

const u8 nexys_a7_01_svf_start[1] = {0};
const u8 nexys_a7_01_svf_end[1] = {0};

static int quiet;
void xil_printf(const char *f, ...)
{
    va_list ap;
    if (quiet) return;
    va_start(ap, f);
    vprintf(f, ap);
    va_end(ap);
}
void outbyte(char c) { (void)c; }
char inbyte(void) { return 'r'; }
int usleep(unsigned long us) { (void)us; return 0; }
void init_platform(void) {}
void cleanup_platform(void) {}

/* ---------------- TAP model ---------------- */
enum { TLR, RTI, SELDR, CAPDR, SDR, EX1DR, PDR, EX2DR, UPDR,
       SELIR, CAPIR, SIR, EX1IR, PIR, EX2IR, UPIR };
#define LOOP_LEN 10000
static int tap = TLR, ir = 0x09, ir_sr, tdo_pin;
static unsigned long long dr_sr; static int dr_len;
static u8 loop_reg[LOOP_LEN];
static int next_state(int s, int tms)
{
    static const int t[16][2] = {
        {RTI, TLR}, {RTI, SELDR}, {CAPDR, SELIR}, {SDR, EX1DR}, {SDR, EX1DR},
        {PDR, UPDR}, {PDR, EX2DR}, {SDR, UPDR}, {RTI, SELDR}, {CAPIR, TLR},
        {SIR, EX1IR}, {SIR, EX1IR}, {PIR, UPIR}, {PIR, EX2IR}, {SIR, UPIR},
        {RTI, SELDR}};
    return t[s][tms];
}
static int dr_out(void)
{
    if (ir == 0x22) return loop_reg[0];
    return (int)(dr_sr & 1U);
}
static void tap_rise(int tms, int tdi)
{
    switch (tap) {
    case CAPIR: ir_sr = 0x01; break;
    case SIR: ir_sr = (ir_sr >> 1) | (tdi << 5); break;
    case CAPDR:
        if (ir == 0x09) { dr_sr = 0x03631093ULL; dr_len = 32; }
        else if (ir != 0x22) { dr_sr = 0; dr_len = 1; }
        break;
    case SDR:
        if (ir == 0x22) {
            memmove(loop_reg, loop_reg + 1, LOOP_LEN - 1);
            loop_reg[LOOP_LEN - 1] = (u8)tdi;
        } else {
            dr_sr = (dr_sr >> 1) | ((unsigned long long)tdi << (dr_len - 1));
        }
        break;
    case UPIR: ir = ir_sr; break;
    case TLR: ir = 0x09; break;
    }
    tap = next_state(tap, tms);
}
static void tap_fall(void)
{
    if (tap == SIR) tdo_pin = ir_sr & 1;
    else if (tap == SDR) tdo_pin = dr_out();
}

/* Rising-edge trace: 2 bits per edge (tms | tdi<<1). */
static u8 *trace; static size_t trace_n, trace_cap;
static int pin_tck, pin_tms, pin_tdi;
static void pins(int tck, int tms, int tdi)
{
    if (pin_tck && !tck) tap_fall();
    if (!pin_tck && tck) {
        if (trace_n == trace_cap) {
            trace_cap = trace_cap ? trace_cap * 2 : 4096;
            trace = realloc(trace, trace_cap);
        }
        trace[trace_n++] = (u8)(tms | (tdi << 1));
        tap_rise(tms, tdi);
    }
    pin_tck = tck; pin_tms = tms; pin_tdi = tdi;
}

/* ---------------- GPIO + shifter model ---------------- */
static u32 gpio_out;
static int engine_en; static u32 clkdiv = 5, cfg = 0x1F, cycles;
static int eng_tdi;
static u32 rxq[1024]; static int rx_head, rx_tail, rx_max;
static int rx_count(void) { return rx_tail - rx_head; }

static void mux_update(void)
{
    if (!engine_en) pins(gpio_out & 1, (gpio_out >> 1) & 1, (gpio_out >> 2) & 1);
}
static void engine_word(u32 data)
{
    int n = (int)(cfg & 0x1F) + 1, mode = (cfg >> 8) & 1;
    int tms_last = (cfg >> 9) & 1, cap = (cfg >> 10) & 1, i;
    u32 got = 0;
    for (i = 0; i < n; i++) {
        int b = (int)((data >> i) & 1U), tms;
        if (mode) { tms = b; } else { eng_tdi = b; tms = tms_last && (i == n - 1); }
        pins(0, tms, eng_tdi);
        pins(1, tms, eng_tdi);
        got |= (u32)tdo_pin << i;
        cycles += 2U * clkdiv;
    }
    pins(0, pin_tms, eng_tdi);
    if (cap) {
        if (rx_count() >= 256) { printf("FAIL: RX FIFO overflow (engine would stall)\n"); exit(1); }
        rxq[rx_tail++ & 1023] = got;
        if (rx_count() > rx_max) rx_max = rx_count();
    }
}

#define GPIO_BASE 0x40000000U
void Xil_Out32(UINTPTR a, u32 v)
{
    if (a == GPIO_BASE + XGPIO_DATA_OFFSET) { gpio_out = v; mux_update(); return; }
    if (a >= GPIO_BASE && a < GPIO_BASE + 0x10000U) return;
    switch ((u32)a - JSH_BASEADDR) {
    case JSH_CTRL_OFFSET:
        if (v & JSH_CTRL_FLUSH) { rx_head = rx_tail = 0; }
        if ((v & 1U) && !engine_en) { engine_en = 1; pins(0, 0, 0); eng_tdi = 0; }
        else if (!(v & 1U) && engine_en) { engine_en = 0; mux_update(); }
        return;
    case JSH_CLKDIV_OFFSET: clkdiv = v ? v : 1; return;
    case JSH_CFG_OFFSET: cfg = v; return;
    case JSH_DATA_OFFSET:
        if (!engine_en) { printf("FAIL: DATA write with engine off\n"); exit(1); }
        engine_word(v); return;
    }
    printf("FAIL: write to unknown address 0x%08x\n", (unsigned)a); exit(1);
}
u32 Xil_In32(UINTPTR a)
{
    if (a == GPIO_BASE + XGPIO_DATA2_OFFSET) return (u32)tdo_pin;
    if (a >= GPIO_BASE && a < GPIO_BASE + 0x10000U) return 0;
    switch ((u32)a - JSH_BASEADDR) {
    case JSH_ID_OFFSET: return JSH_ID_VALUE;
    case JSH_CYCLES_OFFSET: cycles += 7; return cycles;
    case JSH_STATUS_OFFSET:
        return (rx_count() == 0 ? JSH_STATUS_RX_EMPTY : 0U) | JSH_STATUS_TX_EMPTY;
    case JSH_TDO_OFFSET:
        if (rx_count() == 0) return 0;
        return rxq[rx_head++ & 1023];
    }
    printf("FAIL: read of unknown address 0x%08x\n", (unsigned)a); exit(1);
}

static XGpio_Config gcfg = {GPIO_BASE};
XGpio_Config *XGpio_LookupConfig(UINTPTR b) { (void)b; return &gcfg; }
int XGpio_CfgInitialize(XGpio *g, XGpio_Config *c, UINTPTR b) { (void)c; g->BaseAddress = b; return 0; }
void XGpio_SetDataDirection(XGpio *g, unsigned ch, u32 m) { (void)g; (void)ch; (void)m; }
void XGpio_DiscreteWrite(XGpio *g, unsigned ch, u32 v) { if (ch == 1) Xil_Out32(g->BaseAddress, v); }
u32 XGpio_DiscreteRead(XGpio *g, unsigned ch) { (void)g; (void)ch; return (u32)tdo_pin; }

/* ---------------- test driver ---------------- */
struct result { int rc; struct svf_player_ctx ctx; u8 *trace; size_t n; int tap; };

static void reset_world(void)
{
    tap = TLR; ir = 0x09; tdo_pin = 0; pin_tck = pin_tms = pin_tdi = 0;
    memset(loop_reg, 0, sizeof(loop_reg));
    gpio_out = 0; engine_en = 0; rx_head = rx_tail = 0; trace_n = 0;
}

static struct result run(const char *svf, int use_shifter)
{
    struct result r;
    static XGpio g;
    reset_world();
    g.BaseAddress = GPIO_BASE;
    quiet = 1;
    r.rc = play_svf_ctx(&r.ctx, &g, (const u8 *)svf, (u32)strlen(svf), 0, 0, use_shifter);
    quiet = 0;
    r.trace = malloc(trace_n ? trace_n : 1);
    memcpy(r.trace, trace, trace_n);
    r.n = trace_n;
    r.tap = tap;
    return r;
}

static int failures;
static void compare(const char *name, const char *svf, int expect_rc)
{
    struct result a = run(svf, 0), b = run(svf, 1);
    /* GPIO setup makes one extra rising edge (TMS=0, TDI=0) before playback. */
    const u8 *ta = a.trace; size_t na = a.n;
    int ok = 1;
    if (na == b.n + 1 && ta[0] == 0) { ta++; na--; }
    if (na != b.n || memcmp(ta, b.trace, na) != 0) {
        size_t i;
        for (i = 0; i < na && i < b.n && ta[i] == b.trace[i]; i++) {}
        printf("  trace differs: gpio %u edges, shifter %u edges, first diff at %u\n", (unsigned)na, (unsigned)b.n, (unsigned)i);
        ok = 0;
    }
    if (a.rc != b.rc || a.rc != expect_rc) { printf("  rc gpio %d shifter %d expected %d\n", a.rc, b.rc, expect_rc); ok = 0; }
    if (a.ctx.clock_count != b.ctx.clock_count ||
        a.ctx.tdi_bit_count != b.ctx.tdi_bit_count ||
        a.ctx.tdo_check_count != b.ctx.tdo_check_count ||
        a.ctx.tdo_mismatch_count != b.ctx.tdo_mismatch_count ||
        a.ctx.first_mismatch_clock != b.ctx.first_mismatch_clock ||
        a.ctx.first_mismatch_expected != b.ctx.first_mismatch_expected ||
        a.ctx.first_mismatch_actual != b.ctx.first_mismatch_actual) {
        printf("  counters gpio: clk %u tdi %u chk %u mis %u first %u exp %d act %d\n",
               a.ctx.clock_count, a.ctx.tdi_bit_count, a.ctx.tdo_check_count, a.ctx.tdo_mismatch_count,
               a.ctx.first_mismatch_clock, a.ctx.first_mismatch_expected, a.ctx.first_mismatch_actual);
        printf("  counters shf : clk %u tdi %u chk %u mis %u first %u exp %d act %d\n",
               b.ctx.clock_count, b.ctx.tdi_bit_count, b.ctx.tdo_check_count, b.ctx.tdo_mismatch_count,
               b.ctx.first_mismatch_clock, b.ctx.first_mismatch_expected, b.ctx.first_mismatch_actual);
        ok = 0;
    }
    if (a.tap != b.tap) { printf("  final TAP state gpio %d shifter %d\n", a.tap, b.tap); ok = 0; }
    printf("%s %s (edges %u, gpio extra setup edge %d, tdo checks %u, mismatches %u, rx max %d)\n",
           ok ? "PASS" : "FAIL", name, (unsigned)b.n, (int)(a.n - b.n), b.ctx.tdo_check_count,
           b.ctx.tdo_mismatch_count, rx_max);
    rx_max = 0;
    if (!ok) failures++;
    free(a.trace); free(b.trace);
}

static void hex_bits(char *out, const u8 *bits, int len)
{
    /* SVF hex: MSB first; bit 0 = first bit shifted. */
    int nd = (len + 3) / 4, d;
    for (d = 0; d < nd; d++) {
        int base = (nd - 1 - d) * 4, v = 0, k;
        for (k = 3; k >= 0; k--) v = (v << 1) | ((base + k < len) ? bits[base + k] : 0);
        *out++ = "0123456789ABCDEF"[v];
    }
    *out = 0;
}

int main(void)
{
    static char svf[64 * 1024];
    static char ha[3000], hb[3000], hbad[3000];
    static u8 A[LOOP_LEN], B[LOOP_LEN];
    int i;

    compare("idcode", "TRST OFF;\nENDIR IDLE;\nENDDR IDLE;\nSTATE RESET;\nSTATE IDLE;\nFREQUENCY 1E7 HZ;\n"
            "SIR 6 TDI (09) TDO (01) MASK (03);\nSDR 32 TDI (00000000) TDO (03631093) MASK (0FFFFFFF);\n"
            "RUNTEST 100 TCK;\nSTATE RESET;\n", 0);

    compare("bad idcode", "STATE RESET;\nSIR 6 TDI (09);\nSDR 32 TDI (00000000) TDO (03631095);\nSTATE RESET;\n", -1);

    compare("bypass odd lengths", "STATE RESET;\nSIR 6 TDI (3F) TDO (01);\n"
            "SDR 1 TDI (1) TDO (0);\nSDR 2 TDI (3) TDO (2);\nSDR 33 TDI (1FFFFFFFF) TDO (1FFFFFFFE);\n"
            "SDR 7 TDI (55) TDO (2A);\nENDDR DRPAUSE;\nSDR 9 TDI (155) TDO (0AA);\nENDDR IDLE;\nSTATE IDLE;\n", 0);

    compare("smask and pause states", "STATE RESET;\nENDIR IRPAUSE;\nSIR 6 TDI (3F) SMASK (3F);\nENDIR IDLE;\n"
            "SDR 8 TDI (A5) SMASK (FF) TDO (4A);\nRUNTEST IDLE 50 TCK ENDSTATE IDLE;\nSTATE DRPAUSE;\nSTATE IDLE;\n", 0);

    srand(1);
    for (i = 0; i < LOOP_LEN; i++) { A[i] = (u8)(rand() & 1); B[i] = (u8)(rand() & 1); }
    hex_bits(ha, A, LOOP_LEN);
    hex_bits(hb, B, LOOP_LEN);
    snprintf(svf, sizeof(svf), "STATE RESET;\nSIR 6 TDI (22);\nSDR %d TDI (%s);\nSDR %d TDI (%s) TDO (%s);\n"
             "SDR %d TDI (%s) TDO (%s);\nSTATE RESET;\n", LOOP_LEN, ha, LOOP_LEN, hb, ha, LOOP_LEN, ha, hb);
    compare("10000-bit loopback (313 words, RX drain)", svf, 0);

    strcpy(hbad, ha);
    hbad[2000] = (hbad[2000] == '0') ? '4' : '0';
    snprintf(svf, sizeof(svf), "STATE RESET;\nSIR 6 TDI (22);\nSDR %d TDI (%s);\nSDR %d TDI (%s) TDO (%s);\nSTATE RESET;\n",
             LOOP_LEN, ha, LOOP_LEN, hb, hbad);
    compare("10000-bit loopback with one wrong expected digit", svf, -1);

    printf(failures ? "HOST TEST: FAIL (%d)\n" : "HOST TEST: PASS\n", failures);
    return failures ? 1 : 0;
}
