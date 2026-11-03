#include "qnx_platform.h"

#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <time.h>

#if defined(__QNX__)
#include <sys/neutrino.h>
#include <pthread.h>
#endif

static char g_last_error[128];

static void set_error(const char *what)
{
    int e = errno;
    snprintf(g_last_error, sizeof(g_last_error), "%s: %s", what, strerror(e));
}

const char *moq_qnx_last_error(void)
{
    return g_last_error[0] ? g_last_error : "ok";
}

#if defined(__QNX__)

int moq_qnx_set_realtime(int prio)
{
    struct sched_param p;
    memset(&p, 0, sizeof(p));
    p.sched_priority = prio;
    if (pthread_setschedparam(pthread_self(), SCHED_FIFO, &p) != 0) {
        set_error("pthread_setschedparam(SCHED_FIFO)");
        return -1;
    }
    return 0;
}

int moq_qnx_set_normal(void)
{
    struct sched_param p;
    memset(&p, 0, sizeof(p));
    p.sched_priority = 0;
    if (pthread_setschedparam(pthread_self(), SCHED_OTHER, &p) != 0) {
        set_error("pthread_setschedparam(SCHED_OTHER)");
        return -1;
    }
    return 0;
}

int moq_qnx_pin_cpu(int cpu)
{
    /* 64-bit runmask: our targets are <= 64 cores. */
    if (ThreadCtl(_NTO_TCTL_RUNMASK_GET_AND_SET_INHERIT,
                  (void *)(uintptr_t)(1ULL << cpu)) == -1) {
        set_error("ThreadCtl(RUNMASK)");
        return -1;
    }
    return 0;
}

#else /* host stubs, so the layer is testable off-target */

int moq_qnx_set_realtime(int prio)
{
    (void)prio;
    errno = ENOTSUP;
    set_error("stub: not QNX");
    return -1;
}

int moq_qnx_set_normal(void)
{
    errno = ENOTSUP;
    set_error("stub: not QNX");
    return -1;
}

int moq_qnx_pin_cpu(int cpu)
{
    (void)cpu;
    errno = ENOTSUP;
    set_error("stub: not QNX");
    return -1;
}

#endif /* __QNX__ */

uint64_t moq_qnx_mono_ns(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000000000ULL + (uint64_t)ts.tv_nsec;
}
