/*
 * moq_source_feeder.c — reference "camera" feeder for the media_source C API.
 *
 * Reads an FLV file and pushes its frames through the C API exactly the way a
 * camera SDK would: it parses nothing but the container, and hands the encoded
 * H.264/AAC payloads to moq_source_push_video() / moq_source_push_audio().
 *
 * It exists for two reasons:
 *   1. it exercises the public C API end to end without camera hardware;
 *   2. it is the demo "device-side process" for the automotive scenario.
 *
 * Build: compiled into the moqlivecast binary (see integration notes below),
 * because the C API lives in the server process, not in a shared library.
 *
 * Usage (inside the server):
 *     MOQ_FEED_FILE=/data/media/sample.flv \
 *     MOQ_FEED_APP=anon MOQ_FEED_STREAM=cam0 ./moqlivecast config.yml
 */
#define _POSIX_C_SOURCE 200809L

#include "moq_source_c_api.h"

#include <errno.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#define FEED_LOOP_GAP_MS   40
#define FEED_MAX_LAG_MS    400   /* drop frames later than this (real-time) */

typedef struct {
    char        file[512];
    char        app[64];
    char        stream[64];
    int         loop;
    int         realtime;
    moq_source_t* src;        /* created/started on the uv loop thread */
    pthread_t   thread;
    volatile int running;
    uint64_t    frames;
    uint64_t    dropped;
} feeder_t;

static int64_t now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (int64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

static void sleep_ms(int64_t ms) {
    struct timespec ts;
    if (ms <= 0) return;
    ts.tv_sec  = (time_t)(ms / 1000);
    ts.tv_nsec = (long)((ms % 1000) * 1000000L);
    nanosleep(&ts, NULL);
}

static int read_exact(FILE* fp, void* buf, size_t n) {
    return fread(buf, 1, n, fp) == n ? 0 : -1;
}

static uint32_t be24(const uint8_t* p) {
    return ((uint32_t)p[0] << 16) | ((uint32_t)p[1] << 8) | p[2];
}

static int32_t be24_signed(const uint8_t* p) {
    int32_t v = (int32_t)be24(p);
    if (v & 0x800000) v |= ~0xFFFFFF;      /* sign-extend 24 -> 32 */
    return v;
}

/* Push one FLV video tag. */
static void feed_video(moq_source_t* s, const uint8_t* data, size_t len,
                       int64_t dts, int64_t pts) {
    if (len < 5) return;
    const uint8_t frame_type = (uint8_t)(data[0] >> 4);
    const uint8_t codec_id   = (uint8_t)(data[0] & 0x0F);
    if (codec_id != 7) return;              /* only AVC here */

    const uint8_t avc_packet_type = data[1];
    const uint8_t* payload = data + 5;
    const size_t   plen    = len - 5;

    if (avc_packet_type == 0) {             /* AVCDecoderConfigurationRecord */
        moq_source_push_video_config(s, MOQ_CODEC_H264, payload, plen);
        return;
    }
    if (avc_packet_type != 1) return;       /* 2 = end of sequence */

    moq_video_frame_t f;
    memset(&f, 0, sizeof(f));
    f.data        = payload;
    f.len         = plen;
    f.dts_ms      = dts;
    f.pts_ms      = pts;
    f.is_keyframe = (frame_type == 1);
    f.format      = MOQ_BITSTREAM_AVCC;     /* FLV carries AVCC */
    moq_source_push_video(s, &f);
}

/* Push one FLV audio tag. */
static void feed_audio(moq_source_t* s, const uint8_t* data, size_t len,
                       int64_t dts, int64_t pts) {
    if (len < 2) return;
    const uint8_t sound_format = (uint8_t)(data[0] >> 4);
    if (sound_format != 10) return;         /* only AAC here */

    const uint8_t aac_packet_type = data[1];
    const uint8_t* payload = data + 2;
    const size_t   plen    = len - 2;

    if (aac_packet_type == 0) {             /* AudioSpecificConfig */
        moq_source_push_audio_config(s, payload, plen);
        return;
    }
    moq_source_push_audio(s, payload, plen, dts, pts, MOQ_AUDIO_AAC_RAW);
}

static int feed_once(moq_source_t* s, feeder_t* f, int64_t* last_out_dts) {
    FILE* fp = fopen(f->file, "rb");
    if (!fp) {
        fprintf(stderr, "[feeder] cannot open %s: %s\n", f->file, strerror(errno));
        return -1;
    }

    uint8_t hdr[9];
    if (read_exact(fp, hdr, sizeof(hdr)) < 0 || memcmp(hdr, "FLV", 3) != 0) {
        fprintf(stderr, "[feeder] %s is not an FLV\n", f->file);
        fclose(fp);
        return -1;
    }
    const uint32_t data_offset = ((uint32_t)hdr[5] << 24) | ((uint32_t)hdr[6] << 16) |
                                 ((uint32_t)hdr[7] << 8) | hdr[8];
    fseek(fp, (long)data_offset, SEEK_SET);

    const int64_t wall_start = now_ms();
    int64_t first_raw_dts = -1;
    int64_t first_out_dts = -1;
    int64_t base = (last_out_dts && *last_out_dts >= 0) ? *last_out_dts + FEED_LOOP_GAP_MS : 0;

    for (;;) {
        uint8_t th[11];
        if (read_exact(fp, th, sizeof(th)) < 0) break;

        const uint8_t  tag_type = th[0];
        const uint32_t size     = be24(th + 1);
        int64_t        dts      = (int64_t)be24(th + 4) | ((int64_t)th[7] << 24);

        uint8_t* body = (uint8_t*)malloc(size ? size : 1);
        if (!body) break;
        if (read_exact(fp, body, size) < 0) { free(body); break; }

        uint8_t prev[4];
        if (read_exact(fp, prev, 4) < 0) { free(body); break; }

        if (first_raw_dts < 0) first_raw_dts = dts;
        int64_t out_dts = base + (dts - first_raw_dts);
        if (last_out_dts && *last_out_dts >= 0 && out_dts <= *last_out_dts) {
            out_dts = *last_out_dts + 1;
        }

        if (tag_type == 9) {                 /* video */
            int64_t cts = (size >= 5) ? be24_signed(body + 2) : 0;
            feed_video(s, body, size, out_dts, out_dts + cts);
        } else if (tag_type == 8) {          /* audio */
            feed_audio(s, body, size, out_dts, out_dts);
        } else {
            free(body);
            continue;                        /* script data etc. */
        }

        if (f->realtime) {
            if (first_out_dts < 0) first_out_dts = out_dts;
            int64_t due = wall_start + (out_dts - first_out_dts);
            int64_t lag = now_ms() - due;
            if (lag > FEED_MAX_LAG_MS) {
                f->dropped++;                /* too late: skip, never burst */
            } else if (lag < 0) {
                sleep_ms(-lag);
            }
        }

        f->frames++;
        if (last_out_dts) *last_out_dts = out_dts;
        free(body);
    }

    fclose(fp);
    return 0;
}

/* Singleton: one feeder per process is enough for a demo. */
static feeder_t g;
static int g_attached = 0;

static void* feeder_thread(void* arg) {
    feeder_t* f = (feeder_t*)arg;
    int64_t last_out_dts = -1;
    int rounds = 0;

    /* Only push_* here: those are the thread-safe calls. */
    do {
        if (feed_once(f->src, f, &last_out_dts) < 0) break;
        ++rounds;
    } while (f->loop && f->running);

    fprintf(stderr, "[feeder] pump done rounds=%d frames=%llu dropped=%llu\n",
            rounds, (unsigned long long)f->frames, (unsigned long long)f->dropped);
    return NULL;
}

/*
 * Must be called on the uv loop thread: moq_source_create/start are loop-affine.
 * In moq.cpp this is one line right before uv_run().
 */
int moq_feeder_attach(const char* file, const char* app, const char* stream,
                      int loop, int realtime) {
    if (g_attached) return -1;
    memset(&g, 0, sizeof(g));
    snprintf(g.file, sizeof(g.file), "%s", file);
    snprintf(g.app, sizeof(g.app), "%s", app);
    snprintf(g.stream, sizeof(g.stream), "%s", stream);
    g.loop = loop;
    g.realtime = realtime;

    g.src = moq_source_create(g.app, g.stream, "flv-feeder");
    if (!g.src) {
        fprintf(stderr, "[feeder] create failed: %s\n", moq_source_last_error());
        return -1;
    }
    if (moq_source_start(g.src) < 0) {
        fprintf(stderr, "[feeder] start failed: %s\n", moq_source_last_error());
        moq_source_destroy(g.src);
        g.src = NULL;
        return -1;
    }

    g.running = 1;
    if (pthread_create(&g.thread, NULL, feeder_thread, &g) != 0) {
        g.running = 0;
        moq_source_stop(g.src);
        moq_source_destroy(g.src);
        g.src = NULL;
        return -1;
    }

    g_attached = 1;
    fprintf(stderr, "[feeder] attached file=%s -> %s/%s loop=%d realtime=%d\n",
            g.file, g.app, g.stream, g.loop, g.realtime);
    return 0;
}

/* Must be called on the uv loop thread, after uv_run() returns. */
void moq_feeder_detach(void) {
    if (!g_attached) return;
    g.running = 0;
    pthread_join(g.thread, NULL);       /* pump stops within one frame interval */
    moq_source_stop(g.src);
    moq_source_destroy(g.src);
    g.src = NULL;
    g_attached = 0;
    fprintf(stderr, "[feeder] detached\n");
}
