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

/* Channel 2 (JA7..JA10) receives TCK/TMS/TDI driven by the programmer board. */
#define JA_IN_BIT_TCK 0x00000001
#define JA_IN_BIT_TMS 0x00000002
#define JA_IN_BIT_TDI 0x00000004

/* Channel 1 (JA1..JA4) drives TDO back towards the programmer board. */
#define JA_OUT_BIT_TDO 0x00000001

/*
 * Edge waits are bounded by a poll budget rather than a timer peripheral. One
 * poll is a single AXI GPIO read, so the budget is roughly 0.2 us to 0.5 us per
 * count on a 100 MHz MicroBlaze.
 */
#define TCK_FIRST_EDGE_POLL_LIMIT 200000000U
#define TCK_EDGE_POLL_LIMIT 20000000U

/* Deliberately high so a RUNTEST delay never expires the next edge wait. */
#define POLLS_PER_US_ESTIMATE 10U
#define MAX_POLL_BONUS 400000000U

#define MISMATCH_LOG_DEPTH 16
#define MISMATCH_ABORT_LIMIT 64
#define ERROR_TEXT_LEN 96
#define MONITOR_LOG_DEPTH 32
#define JA_TEST_DELAY_US 300000

extern const u8 nexys_a7_01_svf_start[];
extern const u8 nexys_a7_01_svf_end[];

struct mismatch_record {
    u32 clock;
    int tap_state;
    int expected_tms;
    int actual_tms;
    int expected_tdi;
    int actual_tdi;
};

struct jtag_verifier_ctx {
    XGpio *gpio;
    const u8 *svf_data;
    u32 svf_size;
    u32 svf_pos;

    u32 out_shadow;
    u32 last_inputs;
    u32 next_edge_poll_bonus;

    u32 clock_count;
    u32 tms_check_count;
    u32 tms_mismatch_count;
    u32 tdi_check_count;
    u32 tdi_mismatch_count;
    u32 tdo_drive_count;
    u32 edge_timeout_count;

    struct mismatch_record mismatches[MISMATCH_LOG_DEPTH];
    u32 mismatch_log_used;
    u32 mismatch_clock_count;

    char error_text[ERROR_TEXT_LEN];
    int error_line;
    int have_error;

    int dry_run;
    int fatal;
};

/*
 * Both boards must parse byte-identical SVF text, otherwise the two libxsvf
 * instances generate different clock sequences and the capture desyncs. These
 * strings are duplicated verbatim in ../app_mb_svf_player/svf_player.c.
 */
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

static const u8 jtag_loop_svf[] =
    "TRST OFF;\n"
    "ENDIR IDLE;\n"
    "ENDDR IDLE;\n"
    "STATE RESET;\n"
    "STATE IDLE;\n"
    "SIR 6 TDI (09);\n"
    "SDR 32 TDI (00000000) TDO (03631093) MASK (0fffffff);\n"
    "SIR 6 TDI (14);\n"
    "SDR 16 TDI (55aa) TDO (1234) MASK (ffff);\n"
    "RUNTEST 8 TCK;\n"
    "SIR 6 TDI (3f);\n"
    "STATE RESET;\n";

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

static void verifier_write_outputs(struct jtag_verifier_ctx *ctx)
{
    XGpio_WriteReg(ctx->gpio->BaseAddress, XGPIO_DATA_OFFSET,
                   ctx->out_shadow & JA_OUT_MASK);
}

static u32 read_ja_inputs(XGpio *Gpio)
{
    return XGpio_ReadReg(Gpio->BaseAddress, XGPIO_DATA2_OFFSET);
}

/*
 * Spins on the TCK input until it reaches want_high. The word that satisfied
 * the test is returned through sampled so TMS/TDI can be read from the very
 * same bus access that detected the edge.
 */
static int wait_for_tck_level(struct jtag_verifier_ctx *ctx, u32 want_high,
                              u32 poll_limit, u32 *sampled)
{
    UINTPTR base = ctx->gpio->BaseAddress;
    u32 polls = 0U;
    u32 in;

    for (;;) {
        in = XGpio_ReadReg(base, XGPIO_DATA2_OFFSET);
        if (((in & JA_IN_BIT_TCK) != 0U) == (want_high != 0U)) {
            break;
        }

        polls++;
        if (polls >= poll_limit) {
            ctx->last_inputs = in;
            *sampled = in;
            return -1;
        }
    }

    ctx->last_inputs = in;
    *sampled = in;

    return 0;
}

static u32 poll_bonus_from_usecs(long usecs)
{
    unsigned long bonus;

    if (usecs <= 0) {
        return 0U;
    }

    bonus = (unsigned long)usecs;
    if (bonus > (unsigned long)(MAX_POLL_BONUS / POLLS_PER_US_ESTIMATE)) {
        return MAX_POLL_BONUS;
    }

    return (u32)(bonus * POLLS_PER_US_ESTIMATE);
}

/*
 * Presents the TDO bit the SVF file expects the target to return. Real TAPs
 * update TDO on the falling TCK edge, and so does this, which leaves the whole
 * low phase plus the rising edge as the programmer's sampling window.
 */
static void drive_tdo(struct jtag_verifier_ctx *ctx, int tdo)
{
    if (tdo > 0) {
        ctx->out_shadow |= (u32)JA_OUT_BIT_TDO;
    } else {
        ctx->out_shadow &= ~(u32)JA_OUT_BIT_TDO;
    }

    verifier_write_outputs(ctx);

    if (tdo >= 0) {
        ctx->tdo_drive_count++;
    }
}

static void log_mismatch(struct jtag_verifier_ctx *ctx, struct libxsvf_host *h,
                         int expected_tms, int actual_tms, int expected_tdi,
                         int actual_tdi)
{
    struct mismatch_record *rec;

    if (ctx->mismatch_log_used >= MISMATCH_LOG_DEPTH) {
        return;
    }

    rec = &ctx->mismatches[ctx->mismatch_log_used];
    ctx->mismatch_log_used++;

    rec->clock = ctx->clock_count;
    rec->tap_state = (int)h->tap_state;
    rec->expected_tms = expected_tms;
    rec->actual_tms = actual_tms;
    rec->expected_tdi = expected_tdi;
    rec->actual_tdi = actual_tdi;
}

static int mb_jtag_setup(struct libxsvf_host *h)
{
    struct jtag_verifier_ctx *ctx = (struct jtag_verifier_ctx *)h->user_data;

    ctx->svf_pos = 0;
    ctx->out_shadow = 0;
    ctx->last_inputs = 0;
    ctx->next_edge_poll_bonus = 0;
    ctx->clock_count = 0;
    ctx->tms_check_count = 0;
    ctx->tms_mismatch_count = 0;
    ctx->tdi_check_count = 0;
    ctx->tdi_mismatch_count = 0;
    ctx->tdo_drive_count = 0;
    ctx->edge_timeout_count = 0;
    ctx->mismatch_log_used = 0;
    ctx->mismatch_clock_count = 0;
    ctx->error_text[0] = '\0';
    ctx->error_line = 0;
    ctx->have_error = 0;
    ctx->fatal = 0;

    if (ctx->dry_run == 0) {
        configure_ja_gpio(ctx->gpio);
        verifier_write_outputs(ctx);
    }

    return 0;
}

static int mb_jtag_shutdown(struct libxsvf_host *h)
{
    struct jtag_verifier_ctx *ctx = (struct jtag_verifier_ctx *)h->user_data;

    if (ctx->dry_run == 0) {
        ctx->out_shadow = 0;
        verifier_write_outputs(ctx);
    }

    return 0;
}

static int mb_jtag_pulse_tck(struct libxsvf_host *h, int tms, int tdi, int tdo,
                             int rmask, int sync)
{
    struct jtag_verifier_ctx *ctx = (struct jtag_verifier_ctx *)h->user_data;
    u32 poll_limit;
    u32 sampled = 0U;
    int expected_tms;
    int actual_tms;
    int actual_tdi;
    int mismatch = 0;

    (void)rmask;
    (void)sync;

    if (ctx->fatal != 0) {
        return -1;
    }

    if (ctx->dry_run != 0) {
        ctx->clock_count++;
        return (tdo >= 0) ? tdo : 0;
    }

    poll_limit = (ctx->clock_count == 0U) ? TCK_FIRST_EDGE_POLL_LIMIT
                                         : TCK_EDGE_POLL_LIMIT;
    poll_limit += ctx->next_edge_poll_bonus;
    ctx->next_edge_poll_bonus = 0U;

    /*
     * The programmer leaves TCK low between runs and parks it high in its own
     * setup callback, so the first clock is the falling edge after TCK goes
     * high. Without this the idle low level would be mistaken for clock 1.
     */
    if (ctx->clock_count == 0U) {
        if (wait_for_tck_level(ctx, 1U, poll_limit, &sampled) != 0) {
            ctx->edge_timeout_count++;
            ctx->fatal = 1;
            return -1;
        }
    }

    if (wait_for_tck_level(ctx, 0U, poll_limit, &sampled) != 0) {
        ctx->edge_timeout_count++;
        ctx->fatal = 1;
        return -1;
    }

    /* Keep this immediately after the falling edge so TDO settles early. */
    drive_tdo(ctx, tdo);

    actual_tms = ((sampled & JA_IN_BIT_TMS) != 0U) ? 1 : 0;
    actual_tdi = ((sampled & JA_IN_BIT_TDI) != 0U) ? 1 : 0;
    expected_tms = (tms != 0) ? 1 : 0;

    ctx->clock_count++;

    ctx->tms_check_count++;
    if (actual_tms != expected_tms) {
        ctx->tms_mismatch_count++;
        mismatch = 1;
    }

    if (tdi >= 0) {
        ctx->tdi_check_count++;
        if (actual_tdi != ((tdi != 0) ? 1 : 0)) {
            ctx->tdi_mismatch_count++;
            mismatch = 1;
        }
    }

    if (mismatch != 0) {
        ctx->mismatch_clock_count++;
        log_mismatch(ctx, h, expected_tms, actual_tms, tdi, actual_tdi);
    }

    if (wait_for_tck_level(ctx, 1U, TCK_EDGE_POLL_LIMIT, &sampled) != 0) {
        ctx->edge_timeout_count++;
        ctx->fatal = 1;
        return -1;
    }

    /* A mismatch storm means the two sides have lost lockstep; stop early. */
    if ((ctx->tms_mismatch_count + ctx->tdi_mismatch_count) >=
        MISMATCH_ABORT_LIMIT) {
        ctx->fatal = 1;
        return -1;
    }

    return (tdo >= 0) ? tdo : 0;
}

static void mb_jtag_udelay(struct libxsvf_host *h, long usecs, int tms,
                           long num_tck)
{
    struct jtag_verifier_ctx *ctx = (struct jtag_verifier_ctx *)h->user_data;

    while (num_tck > 0) {
        if (mb_jtag_pulse_tck(h, tms, -1, -1, 0, 0) < 0) {
            return;
        }
        num_tck--;
    }

    /*
     * The programmer sleeps here, so nothing is captured. Extend the next edge
     * wait instead of sleeping, because our clock is not the programmer's.
     */
    ctx->next_edge_poll_bonus = poll_bonus_from_usecs(usecs);
}

static int mb_jtag_getbyte(struct libxsvf_host *h)
{
    struct jtag_verifier_ctx *ctx = (struct jtag_verifier_ctx *)h->user_data;

    if (ctx->svf_pos >= ctx->svf_size) {
        return -1;
    }

    return (int)ctx->svf_data[ctx->svf_pos++];
}

static int mb_jtag_sync(struct libxsvf_host *h)
{
    (void)h;
    return 0;
}

static void mb_jtag_pulse_sck(struct libxsvf_host *h)
{
    (void)h;
}

static void mb_jtag_set_trst(struct libxsvf_host *h, int value)
{
    (void)h;
    (void)value;
}

static int mb_jtag_set_frequency(struct libxsvf_host *h, int frequency_hz)
{
    (void)h;
    (void)frequency_hz;
    return 0;
}

static void mb_jtag_report_device(struct libxsvf_host *h, unsigned long idcode)
{
    (void)h;
    (void)idcode;
}

/*
 * Reporting callbacks stay silent during a capture. A blocking UART write
 * between two TCK edges is long enough to miss the programmer's next clock.
 */
static void mb_jtag_report_status(struct libxsvf_host *h, const char *message)
{
    (void)h;
    (void)message;
}

static void mb_jtag_report_error(struct libxsvf_host *h, const char *file,
                                 int line, const char *message)
{
    struct jtag_verifier_ctx *ctx = (struct jtag_verifier_ctx *)h->user_data;
    int i;

    (void)file;

    if (ctx->have_error != 0) {
        return;
    }

    ctx->have_error = 1;
    ctx->error_line = line;

    for (i = 0; (i < (ERROR_TEXT_LEN - 1)) && (message[i] != '\0'); i++) {
        ctx->error_text[i] = message[i];
    }
    ctx->error_text[i] = '\0';
}

static void *mb_jtag_realloc(struct libxsvf_host *h, void *ptr, int size,
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

static void init_verifier_host(struct libxsvf_host *host,
                               struct jtag_verifier_ctx *ctx)
{
    memset(host, 0, sizeof(*host));

    host->setup = mb_jtag_setup;
    host->shutdown = mb_jtag_shutdown;
    host->udelay = mb_jtag_udelay;
    host->getbyte = mb_jtag_getbyte;
    host->sync = mb_jtag_sync;
    host->pulse_tck = mb_jtag_pulse_tck;
    host->pulse_sck = mb_jtag_pulse_sck;
    host->set_trst = mb_jtag_set_trst;
    host->set_frequency = mb_jtag_set_frequency;
    host->report_device = mb_jtag_report_device;
    host->report_status = mb_jtag_report_status;
    host->report_error = mb_jtag_report_error;
    host->realloc = mb_jtag_realloc;
    host->user_data = ctx;
}

static void print_svf_blob_info(void)
{
    u32 svf_addr = (u32)(UINTPTR)nexys_a7_01_svf_start;
    u32 svf_end_addr = (u32)(UINTPTR)nexys_a7_01_svf_end;
    u32 svf_size = get_svf_size();

    xil_printf("SVF blob address: 0x%08x\r\n", svf_addr);
    xil_printf("SVF blob size:    %u bytes\r\n", svf_size);

    if ((svf_addr < XPAR_MIG_0_BASEADDRESS) ||
        (svf_end_addr > (XPAR_MIG_0_HIGHADDRESS + 1U))) {
        xil_printf("WARNING: SVF blob is not inside MIG address range.\r\n");
    }
}

static void print_input_levels(XGpio *Gpio)
{
    u32 inputs = read_ja_inputs(Gpio);

    xil_printf("JA inputs: 0x%08x  TCK(JA7)=%d TMS(JA8)=%d TDI(JA9)=%d\r\n",
               inputs,
               ((inputs & JA_IN_BIT_TCK) != 0U) ? 1 : 0,
               ((inputs & JA_IN_BIT_TMS) != 0U) ? 1 : 0,
               ((inputs & JA_IN_BIT_TDI) != 0U) ? 1 : 0);
}

static void print_verify_report(struct jtag_verifier_ctx *ctx, int rc)
{
    u32 i;

    xil_printf("\r\n--- JTAG verifier report ---\r\n");
    xil_printf("libxsvf rc: %d\r\n", rc);
    xil_printf("Captured TCK clocks: %u\r\n", ctx->clock_count);
    xil_printf("TMS compares: %u, mismatches: %u\r\n",
               ctx->tms_check_count, ctx->tms_mismatch_count);
    xil_printf("TDI compares: %u, mismatches: %u\r\n",
               ctx->tdi_check_count, ctx->tdi_mismatch_count);
    xil_printf("TDO bits driven: %u\r\n", ctx->tdo_drive_count);
    xil_printf("TCK edge timeouts: %u\r\n", ctx->edge_timeout_count);

    if (ctx->have_error != 0) {
        xil_printf("libxsvf error at line %d: ", ctx->error_line);
        print_limited(ctx->error_text, ERROR_TEXT_LEN);
        xil_printf("\r\n");
    }

    for (i = 0; i < ctx->mismatch_log_used; i++) {
        const struct mismatch_record *rec = &ctx->mismatches[i];

        xil_printf("  clk %u in %s: TMS exp %d got %d, TDI exp %d got %d\r\n",
                   rec->clock,
                   libxsvf_state2str((enum libxsvf_tap_state)rec->tap_state),
                   rec->expected_tms, rec->actual_tms,
                   rec->expected_tdi, rec->actual_tdi);
    }

    if (ctx->mismatch_clock_count > ctx->mismatch_log_used) {
        xil_printf("  (%u further mismatching clocks were not logged)\r\n",
                   ctx->mismatch_clock_count - ctx->mismatch_log_used);
    }

    if (ctx->clock_count == 0U) {
        xil_printf("RESULT: FAIL - no JTAG activity captured. "
                   "Check wiring and start the programmer after arming.\r\n");
    } else if (ctx->edge_timeout_count != 0U) {
        xil_printf("RESULT: FAIL - TCK edge timeout after %u clocks. "
                   "The programmer stopped early or is clocking too fast.\r\n",
                   ctx->clock_count);
    } else if ((ctx->tms_mismatch_count != 0U) ||
               (ctx->tdi_mismatch_count != 0U)) {
        xil_printf("RESULT: FAIL - captured JTAG does not match the SVF.\r\n");
    } else if (rc < 0) {
        xil_printf("RESULT: FAIL - SVF playback aborted.\r\n");
    } else {
        xil_printf("RESULT: PASS - captured JTAG matches the SVF.\r\n");
    }
}

static int verify_svf_buffer(XGpio *Gpio, const u8 *svf_data, u32 svf_size,
                             int dry_run)
{
    static struct jtag_verifier_ctx ctx;
    struct libxsvf_host host;
    int rc;

    memset(&ctx, 0, sizeof(ctx));
    ctx.gpio = Gpio;
    ctx.svf_data = svf_data;
    ctx.svf_size = svf_size;
    ctx.dry_run = dry_run;

    init_verifier_host(&host, &ctx);

    if (dry_run != 0) {
        xil_printf("Dry run: parsing SVF without touching the JA pins.\r\n");
    } else {
        xil_printf("Armed. Waiting for TCK on JA7. "
                   "Start playback on the programmer board now.\r\n");
    }

    rc = libxsvf_play(&host, LIBXSVF_MODE_SVF);

    if (dry_run != 0) {
        xil_printf("Dry run finished with rc=%d\r\n", rc);
        xil_printf("Expected TCK clocks for this SVF: %u\r\n", ctx.clock_count);
        if (ctx.have_error != 0) {
            xil_printf("libxsvf error at line %d: ", ctx.error_line);
            print_limited(ctx.error_text, ERROR_TEXT_LEN);
            xil_printf("\r\n");
        }
    } else {
        print_verify_report(&ctx, rc);
    }

    return rc;
}

static void monitor_jtag_lines(XGpio *Gpio)
{
    struct jtag_verifier_ctx ctx;
    u8 tms_log[MONITOR_LOG_DEPTH];
    u8 tdi_log[MONITOR_LOG_DEPTH];
    u32 fall_sample = 0U;
    u32 tmp = 0U;
    u32 logged = 0U;
    u32 clocks = 0U;
    u32 i;

    memset(&ctx, 0, sizeof(ctx));
    ctx.gpio = Gpio;

    configure_ja_gpio(Gpio);

    xil_printf("Monitor armed. Waiting for TCK on JA7. "
               "Start playback on the programmer board now.\r\n");

    if (wait_for_tck_level(&ctx, 1U, TCK_FIRST_EDGE_POLL_LIMIT, &tmp) != 0) {
        xil_printf("TCK never went high. Last inputs: 0x%08x\r\n",
                   ctx.last_inputs);
        return;
    }

    if (wait_for_tck_level(&ctx, 0U, TCK_FIRST_EDGE_POLL_LIMIT,
                           &fall_sample) != 0) {
        xil_printf("No TCK falling edge seen. Last inputs: 0x%08x\r\n",
                   ctx.last_inputs);
        return;
    }

    for (;;) {
        if (logged < MONITOR_LOG_DEPTH) {
            tms_log[logged] = ((fall_sample & JA_IN_BIT_TMS) != 0U) ? 1U : 0U;
            tdi_log[logged] = ((fall_sample & JA_IN_BIT_TDI) != 0U) ? 1U : 0U;
            logged++;
        }
        clocks++;

        if (wait_for_tck_level(&ctx, 1U, TCK_EDGE_POLL_LIMIT, &tmp) != 0) {
            break;
        }
        if (wait_for_tck_level(&ctx, 0U, TCK_EDGE_POLL_LIMIT,
                              &fall_sample) != 0) {
            break;
        }
    }

    xil_printf("Captured %u TCK clocks before the line went idle.\r\n", clocks);
    xil_printf("First %u clocks (sampled on the falling TCK edge):\r\n", logged);

    for (i = 0; i < logged; i++) {
        xil_printf("  clk %u: TMS=%d TDI=%d\r\n", i + 1U,
                   (int)tms_log[i], (int)tdi_log[i]);
    }
}

static void test_tdo_output(XGpio *Gpio)
{
    static const u32 ja_pattern[] = {
        JA_OUT_BIT_TDO,
        0x0,
        JA_OUT_BIT_TDO,
        0x0
    };
    int i;

    configure_ja_gpio(Gpio);

    for (i = 0; i < (int)(sizeof(ja_pattern) / sizeof(ja_pattern[0])); i++) {
        XGpio_DiscreteWrite(Gpio, JA_OUT_CHANNEL, ja_pattern[i] & JA_OUT_MASK);
        usleep(JA_TEST_DELAY_US);
    }

    XGpio_DiscreteWrite(Gpio, JA_OUT_CHANNEL, 0x00000000);
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
    xil_printf("  v - verify captured JTAG against the embedded SVF\r\n");
    xil_printf("  l - verify against the short loop-test SVF\r\n");
    xil_printf("  d - verify against the LED demo SVF\r\n");
    xil_printf("  c - dry run the embedded SVF to count expected clocks\r\n");
    xil_printf("  m - monitor raw TCK/TMS/TDI without comparing\r\n");
    xil_printf("  i - print JA input levels\r\n");
    xil_printf("  t - blink the TDO output on JA1\r\n");
    xil_printf("  r - reset JA outputs low\r\n");
    xil_printf("Input: ");
}

int main(void)
{
    int status;
    XGpio JaGpio;

    init_platform();

    status = init_ja_gpio(&JaGpio);
    if (status != XST_SUCCESS) {
        xil_printf("JA GPIO init failed\r\n");
        while (1);
    }

    configure_ja_gpio(&JaGpio);

    xil_printf("MicroBlaze JTAG verifier ready.\r\n");
    xil_printf("JA7=TCK in, JA8=TMS in, JA9=TDI in, JA1=TDO out.\r\n");
    print_svf_blob_info();
    print_input_levels(&JaGpio);

    while (1) {
        char command;

        print_menu();
        command = read_uart_command();

        if ((command == 'v') || (command == 'V')) {
            (void)verify_svf_buffer(&JaGpio, nexys_a7_01_svf_start,
                                    get_svf_size(), 0);
        } else if ((command == 'l') || (command == 'L')) {
            (void)verify_svf_buffer(&JaGpio, jtag_loop_svf,
                                    (u32)(sizeof(jtag_loop_svf) - 1U), 0);
        } else if ((command == 'd') || (command == 'D')) {
            (void)verify_svf_buffer(&JaGpio, led_demo_svf,
                                    (u32)(sizeof(led_demo_svf) - 1U), 0);
        } else if ((command == 'c') || (command == 'C')) {
            (void)verify_svf_buffer(&JaGpio, nexys_a7_01_svf_start,
                                    get_svf_size(), 1);
        } else if ((command == 'm') || (command == 'M')) {
            monitor_jtag_lines(&JaGpio);
        } else if ((command == 'i') || (command == 'I')) {
            print_input_levels(&JaGpio);
        } else if ((command == 't') || (command == 'T')) {
            xil_printf("Blinking TDO on JA1.\r\n");
            test_tdo_output(&JaGpio);
        } else if ((command == 'r') || (command == 'R')) {
            configure_ja_gpio(&JaGpio);
            xil_printf("JA outputs reset low.\r\n");
        } else {
            xil_printf("Unknown command.\r\n");
        }
    }
}
