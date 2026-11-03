/*
 * QNX 8.0 platform helpers for the moqlivecast media pipeline.
 *
 * Small on purpose: scheduling, affinity, clock. Everything here has a Linux
 * stub so the layer can be unit-tested on the host.
 */
#ifndef MOQ_QNX_PLATFORM_H
#define MOQ_QNX_PLATFORM_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Priority map — see port/qnx/README.md. Higher number = more urgent. */
#define MOQ_QNX_PRIO_SERVO   20 /* demo control loop, not part of the port */
#define MOQ_QNX_PRIO_CAPTURE 10
#define MOQ_QNX_PRIO_ENCODE  8
#define MOQ_QNX_PRIO_NET     5
#define MOQ_QNX_PRIO_STATS   1

/*
 * Put the *calling thread* into SCHED_FIFO at `prio`.
 * Returns 0 on success, -1 on failure (errno set).
 * Requires PROCMGR_AID_PRIORITY; QNX drops it for non-root unless the
 * binary is started with the right ability.
 */
int moq_qnx_set_realtime(int prio);

/* Restore SCHED_OTHER for the calling thread. */
int moq_qnx_set_normal(void);

/* Pin the calling thread to `cpu` (0-based). Returns 0 / -1. */
int moq_qnx_pin_cpu(int cpu);

/* CLOCK_MONOTONIC in nanoseconds — the only clock used for latency math. */
uint64_t moq_qnx_mono_ns(void);

/* Human-readable reason for the last failure, for log lines. */
const char *moq_qnx_last_error(void);

#ifdef __cplusplus
}
#endif

#endif /* MOQ_QNX_PLATFORM_H */
