/*
 * Host-side libxsvf player that records every TCK instead of driving pins.
 *
 * It mirrors the MicroBlaze host in sw/nexys_a7/app_mb_svf_player/svf_player.c:
 * TDI keeps its previous value when libxsvf passes tdi = -1, the pin starts
 * at 0, udelay clocks first and waits afterwards, and TDO always matches.
 *
 * Trace format: one byte per TCK, identical to tools/jbin_model.py:
 *   bit0 TMS, bit1 TDI, bit2 expected TDO, bit3 TDO checked.
 * Events file lines: "<tck> WAIT <us>", "<tck> FREQ <hz>", "<tck> TRST <v>".
 *
 * Usage: svf_record input.svf trace.trc events.txt
 */

#include <stdio.h>
#include <stdlib.h>

#include "libxsvf.h"

struct rec_ctx {
	FILE *svf;
	FILE *trace;
	FILE *events;
	unsigned long long tck;
	int tdi_pin;
};

static int h_setup(struct libxsvf_host *h)
{
	struct rec_ctx *c = h->user_data;
	c->tdi_pin = 0;
	return 0;
}

static int h_shutdown(struct libxsvf_host *h)
{
	(void)h;
	return 0;
}

static int h_pulse_tck(struct libxsvf_host *h, int tms, int tdi, int tdo,
		       int rmask, int sync)
{
	struct rec_ctx *c = h->user_data;
	int b;

	(void)rmask;
	(void)sync;
	if (tdi >= 0)
		c->tdi_pin = tdi ? 1 : 0;
	b = (tms ? 1 : 0) | (c->tdi_pin << 1);
	if (tdo >= 0)
		b |= 8 | ((tdo ? 1 : 0) << 2);
	fputc(b, c->trace);
	c->tck++;
	return tdo >= 0 ? tdo : 0;
}

static void h_udelay(struct libxsvf_host *h, long usecs, int tms, long num_tck)
{
	struct rec_ctx *c = h->user_data;

	while (num_tck-- > 0)
		h_pulse_tck(h, tms, -1, -1, 0, 0);
	if (usecs > 0)
		fprintf(c->events, "%llu WAIT %ld\n", c->tck, usecs);
}

static int h_getbyte(struct libxsvf_host *h)
{
	struct rec_ctx *c = h->user_data;
	return fgetc(c->svf);
}

static void h_set_trst(struct libxsvf_host *h, int v)
{
	struct rec_ctx *c = h->user_data;
	int code = v == 1 ? 1 : v == 0 ? 0 : v == -1 ? 2 : 3;
	fprintf(c->events, "%llu TRST %d\n", c->tck, code);
}

static int h_set_frequency(struct libxsvf_host *h, int v)
{
	struct rec_ctx *c = h->user_data;
	fprintf(c->events, "%llu FREQ %d\n", c->tck, v);
	return 0;
}

static void h_report_error(struct libxsvf_host *h, const char *file, int line,
			   const char *message)
{
	(void)h;
	fprintf(stderr, "[%s:%d] %s\n", file, line, message);
}

static void *h_realloc(struct libxsvf_host *h, void *ptr, int size,
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

int main(int argc, char **argv)
{
	struct rec_ctx ctx = { 0 };
	struct libxsvf_host host = { 0 };
	int rc;

	if (argc != 4) {
		fprintf(stderr, "usage: %s input.svf trace.trc events.txt\n",
			argv[0]);
		return 2;
	}
	ctx.svf = fopen(argv[1], "rb");
	ctx.trace = fopen(argv[2], "wb");
	ctx.events = fopen(argv[3], "w");
	if (!ctx.svf || !ctx.trace || !ctx.events) {
		perror("fopen");
		return 2;
	}
	setvbuf(ctx.svf, NULL, _IOFBF, 1 << 20);
	setvbuf(ctx.trace, NULL, _IOFBF, 1 << 20);

	host.setup = h_setup;
	host.shutdown = h_shutdown;
	host.udelay = h_udelay;
	host.getbyte = h_getbyte;
	host.pulse_tck = h_pulse_tck;
	host.set_trst = h_set_trst;
	host.set_frequency = h_set_frequency;
	host.report_error = h_report_error;
	host.realloc = h_realloc;
	host.user_data = &ctx;

	rc = libxsvf_play(&host, LIBXSVF_MODE_SVF);
	fclose(ctx.trace);
	fclose(ctx.events);
	fclose(ctx.svf);
	fprintf(stderr, "libxsvf rc=%d, %llu TCK\n", rc, ctx.tck);
	return rc < 0 ? 1 : 0;
}
