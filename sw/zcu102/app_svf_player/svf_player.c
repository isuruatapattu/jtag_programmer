#include <stdlib.h>
#include <string.h>

#include "platform.h"
#include "xparameters.h"
#include "xil_printf.h"
#include "xil_types.h"
#include "sleep.h"
#include "xgpio.h"
#include "xgpio_l.h"
#include "xstatus.h"
#include "libxsvf.h"

#define JA_GPIO_BASEADDR XPAR_XGPIO_0_BASEADDR
#define JA_OUT_CHANNEL 1
#define JA_IN_CHANNEL 2
#define JA_OUT_MASK 0x0000000F
#define JA_IN_MASK 0x0000000F

#define JA_BIT_TCK 0x00000001
#define JA_BIT_TMS 0x00000002
#define JA_BIT_TDI 0x00000004
#define JA_BIT_TDO 0x00000001

#define JA_TEST_DELAY_US 300000
#define LED_DEMO_EDGE_DELAY_US 100000
#define STATUS_PRINT_LIMIT 96

extern const u8 nexys_a7_01_svf_start[];
extern const u8 nexys_a7_01_svf_end[];

struct svf_player_ctx {
    XGpio *gpio;
    const u8 *svf_data;
    u32 svf_size;
    u32 svf_pos;
    u32 out_shadow;
    u32 clock_count;
    u32 tdi_bit_count;
    u32 tdo_check_count;
    u32 tdo_mismatch_count;
    u32 first_mismatch_clock;
    u32 edge_delay_us;
    int ignore_tdo;
    int first_mismatch_expected;
    int first_mismatch_actual;
};

static const u8 led_demo_svf[] =
    "TRST OFF;\n"
    "ENDIR IDLE;\n"
    "ENDDR IDLE;\n"
    "STATE RESET;\n"
    "STATE IDLE;\n"
    "FREQUENCY 3 HZ;\n"
    "SIR 6 TDI (09);\n"
    "SDR 32 TDI (00000000);\n"
    "RUNTEST 8 TCK;\n"
    "SIR 6 TDI (14);\n"
    "SDR 16 TDI (55aa);\n"
    "STATE RESET;\n";

static int mb_svf_pulse_tck(struct libxsvf_host *h, int tms, int tdi, int tdo,
                            int rmask, int sync);

static u32 get_svf_size(void)
{
    return (u32)(nexys_a7_01_svf_end - nexys_a7_01_svf_start);
}

static void print_limited(const char *message, int max_chars)
{
    int i;

    for (i = 0; (message[i] != '\0') && (i < max_chars); i++) {
        char ch = message[i];
        if ((ch == '\r') || (ch == '\n')) {
            ch = ' ';
        }
        outbyte(ch);
    }

    if (message[i] != '\0') {
        xil_printf("...");
    }
}

static int init_ja_gpio(XGpio *Gpio)
{
    XGpio_Config *CfgPtr;

    CfgPtr = XGpio_LookupConfig(JA_GPIO_BASEADDR);
    if (CfgPtr == NULL) {
        return XST_FAILURE;
    }

    return XGpio_CfgInitialize(Gpio, CfgPtr, CfgPtr->BaseAddress);
}

static void configure_ja_gpio(XGpio *Gpio)
{
    XGpio_SetDataDirection(Gpio, JA_OUT_CHANNEL, 0x00000000);
    XGpio_SetDataDirection(Gpio, JA_IN_CHANNEL, 0xFFFFFFFF);
    XGpio_DiscreteWrite(Gpio, JA_OUT_CHANNEL, 0x00000000);
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

static void delay_us_long(long usecs)
{
    while (usecs > 0) {
        unsigned int chunk = (usecs > 1000000L) ? 1000000U : (unsigned int)usecs;
        usleep(chunk);
        usecs -= (long)chunk;
    }
}

static void svf_write_outputs(struct svf_player_ctx *ctx)
{
    XGpio_WriteReg(ctx->gpio->BaseAddress, XGPIO_DATA_OFFSET,
                   ctx->out_shadow & JA_OUT_MASK);
}

static int svf_read_tdo(struct svf_player_ctx *ctx)
{
    u32 input_value;

    input_value = XGpio_ReadReg(ctx->gpio->BaseAddress, XGPIO_DATA2_OFFSET);
    return ((input_value & JA_BIT_TDO) != 0U) ? 1 : 0;
}

static int mb_svf_setup(struct libxsvf_host *h)
{
    struct svf_player_ctx *ctx = (struct svf_player_ctx *)h->user_data;

    ctx->svf_pos = 0;
    ctx->out_shadow = JA_BIT_TCK;
    ctx->clock_count = 0;
    ctx->tdi_bit_count = 0;
    ctx->tdo_check_count = 0;
    ctx->tdo_mismatch_count = 0;
    ctx->first_mismatch_clock = 0;
    ctx->first_mismatch_expected = -1;
    ctx->first_mismatch_actual = -1;

    configure_ja_gpio(ctx->gpio);
    svf_write_outputs(ctx);

    return 0;
}

static int mb_svf_shutdown(struct libxsvf_host *h)
{
    struct svf_player_ctx *ctx = (struct svf_player_ctx *)h->user_data;

    ctx->out_shadow = 0;
    svf_write_outputs(ctx);

    return 0;
}

static void mb_svf_udelay(struct libxsvf_host *h, long usecs, int tms,
                          long num_tck)
{
    while (num_tck > 0) {
        (void)mb_svf_pulse_tck(h, tms, -1, -1, 0, 0);
        num_tck--;
    }

    delay_us_long(usecs);
}

static int mb_svf_getbyte(struct libxsvf_host *h)
{
    struct svf_player_ctx *ctx = (struct svf_player_ctx *)h->user_data;

    if (ctx->svf_pos >= ctx->svf_size) {
        return -1;
    }

    return (int)ctx->svf_data[ctx->svf_pos++];
}

static int mb_svf_sync(struct libxsvf_host *h)
{
    (void)h;
    return 0;
}

static int mb_svf_pulse_tck(struct libxsvf_host *h, int tms, int tdi, int tdo,
                            int rmask, int sync)
{
    struct svf_player_ctx *ctx = (struct svf_player_ctx *)h->user_data;
    int line_tdo = 0;
    int should_read_tdo;

    (void)sync;

    if (tms != 0) {
        ctx->out_shadow |= JA_BIT_TMS;
    } else {
        ctx->out_shadow &= ~JA_BIT_TMS;
    }

    if (tdi >= 0) {
        ctx->tdi_bit_count++;
        if (tdi != 0) {
            ctx->out_shadow |= JA_BIT_TDI;
        } else {
            ctx->out_shadow &= ~JA_BIT_TDI;
        }
    }

    ctx->out_shadow |= JA_BIT_TCK;
    svf_write_outputs(ctx);
    if (ctx->edge_delay_us != 0U) {
        usleep(ctx->edge_delay_us);
    }

    ctx->out_shadow &= ~JA_BIT_TCK;
    svf_write_outputs(ctx);
    if (ctx->edge_delay_us != 0U) {
        usleep(ctx->edge_delay_us);
    }

    ctx->out_shadow |= JA_BIT_TCK;
    svf_write_outputs(ctx);
    if (ctx->edge_delay_us != 0U) {
        usleep(ctx->edge_delay_us);
    }

    ctx->clock_count++;

    should_read_tdo = (tdo >= 0) || (rmask != 0);
    if (should_read_tdo) {
        line_tdo = svf_read_tdo(ctx);
        if (tdo >= 0) {
            ctx->tdo_check_count++;
            if ((ctx->ignore_tdo == 0) && (line_tdo != tdo)) {
                ctx->tdo_mismatch_count++;
                if (ctx->first_mismatch_expected < 0) {
                    ctx->first_mismatch_clock = ctx->clock_count;
                    ctx->first_mismatch_expected = tdo;
                    ctx->first_mismatch_actual = line_tdo;
                }
                return -1;
            }
        }
    }

    return line_tdo;
}

static void mb_svf_pulse_sck(struct libxsvf_host *h)
{
    (void)h;
}

static void mb_svf_set_trst(struct libxsvf_host *h, int value)
{
    (void)h;
    (void)value;
}

static int mb_svf_set_frequency(struct libxsvf_host *h, int frequency_hz)
{
    (void)h;
    xil_printf("SVF requested JTAG frequency: %d Hz; using GPIO bit-bang speed.\r\n",
               frequency_hz);
    return 0;
}

static void mb_svf_report_device(struct libxsvf_host *h, unsigned long idcode)
{
    (void)h;
    xil_printf("JTAG IDCODE: 0x%08x\r\n", (u32)idcode);
}

static void mb_svf_report_status(struct libxsvf_host *h, const char *message)
{
    (void)h;
    xil_printf("[SVF] ");
    print_limited(message, STATUS_PRINT_LIMIT);
    xil_printf("\r\n");
}

static void mb_svf_report_error(struct libxsvf_host *h, const char *file,
                                int line, const char *message)
{
    (void)h;
    xil_printf("[SVF ERROR] ");
    print_limited(file, 48);
    xil_printf(":%d ", line);
    print_limited(message, STATUS_PRINT_LIMIT);
    xil_printf("\r\n");
}

static void *mb_svf_realloc(struct libxsvf_host *h, void *ptr, int size,
                            enum libxsvf_mem which)
{
    (void)h;
    (void)which;

    if (size <= 0) {
        free(ptr);
        return NULL;
    }

    return realloc(ptr, (size_t)size);
}

static void init_svf_host(struct libxsvf_host *host, struct svf_player_ctx *ctx)
{
    memset(host, 0, sizeof(*host));

    host->setup = mb_svf_setup;
    host->shutdown = mb_svf_shutdown;
    host->udelay = mb_svf_udelay;
    host->getbyte = mb_svf_getbyte;
    host->sync = mb_svf_sync;
    host->pulse_tck = mb_svf_pulse_tck;
    host->pulse_sck = mb_svf_pulse_sck;
    host->set_trst = mb_svf_set_trst;
    host->set_frequency = mb_svf_set_frequency;
    host->report_device = mb_svf_report_device;
    host->report_status = mb_svf_report_status;
    host->report_error = mb_svf_report_error;
    host->realloc = mb_svf_realloc;
    host->user_data = ctx;
}

static void print_svf_blob_info(void)
{
    u32 svf_addr = (u32)(UINTPTR)nexys_a7_01_svf_start;
    u32 svf_end_addr = (u32)(UINTPTR)nexys_a7_01_svf_end;
    u32 svf_size = get_svf_size();

    xil_printf("SVF blob address: 0x%08x\r\n", svf_addr);
    xil_printf("SVF blob size:    %u bytes\r\n", svf_size);

    if ((svf_addr < XPAR_PSU_DDR_0_BASEADDRESS) ||
        (svf_end_addr > (XPAR_PSU_DDR_0_HIGHADDRESS + 1U))) {
        xil_printf("WARNING: SVF blob is not inside PS DDR address range.\r\n");
    }
}

static int play_svf_buffer(XGpio *Gpio, const u8 *svf_data, u32 svf_size,
                           u32 edge_delay_us, int ignore_tdo)
{
    struct svf_player_ctx ctx;
    struct libxsvf_host host;
    int rc;

    memset(&ctx, 0, sizeof(ctx));
    ctx.gpio = Gpio;
    ctx.svf_data = svf_data;
    ctx.svf_size = svf_size;
    ctx.edge_delay_us = edge_delay_us;
    ctx.ignore_tdo = ignore_tdo;

    init_svf_host(&host, &ctx);

    rc = libxsvf_play(&host, LIBXSVF_MODE_SVF);

    xil_printf("SVF playback finished with rc=%d\r\n", rc);
    xil_printf("TCK clocks: %u, TDI bits: %u, TDO checks: %u\r\n",
               ctx.clock_count, ctx.tdi_bit_count, ctx.tdo_check_count);

    if (ctx.tdo_mismatch_count != 0U) {
        xil_printf("TDO mismatches: %u, first at TCK %u expected %d actual %d\r\n",
                   ctx.tdo_mismatch_count, ctx.first_mismatch_clock,
                   ctx.first_mismatch_expected, ctx.first_mismatch_actual);
    }

    return rc;
}

static int play_embedded_svf(XGpio *Gpio)
{
    xil_printf("Starting embedded SVF playback.\r\n");
    print_svf_blob_info();
    return play_svf_buffer(Gpio, nexys_a7_01_svf_start, get_svf_size(), 0, 0);
}

static int play_led_demo_svf(XGpio *Gpio)
{
    xil_printf("Starting visible LED SVF demo. TDO checks are ignored.\r\n");
    xil_printf("Connect LEDs to J55.1=TCK, J55.3=TMS, J55.5=TDI.\r\n");
    return play_svf_buffer(Gpio, led_demo_svf, (u32)(sizeof(led_demo_svf) - 1U),
                           LED_DEMO_EDGE_DELAY_US, 1);
}

static char read_uart_command(void)
{
    char ch;

    do {
        ch = inbyte();
    } while ((ch == '\r') || (ch == '\n') || (ch == ' ') || (ch == '\t'));

    outbyte(ch);
    xil_printf("\r\n");

    return ch;
}

static void print_menu(void)
{
    xil_printf("\r\nCommands:\r\n");
    xil_printf("  p - play embedded SVF over J55 JTAG\r\n");
    xil_printf("  d - visible LED SVF demo with no target attached\r\n");
    xil_printf("  t - run one J55 output LED test pattern\r\n");
    xil_printf("  r - reset J55 outputs low\r\n");
    xil_printf("Input: ");
}

int main(void)
{
    int status;
    XGpio JaGpio;

    init_platform();

    status = init_ja_gpio(&JaGpio);
    if (status != XST_SUCCESS) {
        xil_printf("J55 GPIO init failed\r\n");
        while (1);
    }

    configure_ja_gpio(&JaGpio);

    xil_printf("ZCU102 SVF player ready.\r\n");
    xil_printf("J55.1=TCK, J55.3=TMS, J55.5=TDI, J55.7=TDO.\r\n");
    print_svf_blob_info();

    while (1) {
        char command;

        print_menu();
        command = read_uart_command();

        if ((command == 'p') || (command == 'P')) {
            (void)play_embedded_svf(&JaGpio);
        } else if ((command == 'd') || (command == 'D')) {
            (void)play_led_demo_svf(&JaGpio);
        } else if ((command == 't') || (command == 'T')) {
            xil_printf("Running J55 output test once.\r\n");
            test_ja_outputs(&JaGpio);
        } else if ((command == 'r') || (command == 'R')) {
            configure_ja_gpio(&JaGpio);
            xil_printf("J55 outputs reset low.\r\n");
        } else {
            xil_printf("Unknown command.\r\n");
        }
    }
}
