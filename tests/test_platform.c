/* Host-side sanity checks for the port layer. These do not prove QNX
 * behaviour — they prove the API shape and the clock are sane, so a broken
 * port layer is caught before it ever reaches the target. */
#include <stdio.h>
#include <stdlib.h>

#include "qnx_platform.h"

static int failures;

#define CHECK(cond)                                                      \
    do {                                                                 \
        if (!(cond)) {                                                   \
            fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); \
            failures++;                                                  \
        }                                                                \
    } while (0)

int main(void)
{
    uint64_t a = moq_qnx_mono_ns();
    uint64_t b = moq_qnx_mono_ns();
    CHECK(b >= a);

    /* 1 ms of busy waiting should advance the monotonic clock by ~1 ms. */
    uint64_t start = moq_qnx_mono_ns();
    while (moq_qnx_mono_ns() - start < 1000000ULL) {
    }
    uint64_t elapsed = moq_qnx_mono_ns() - start;
    CHECK(elapsed >= 1000000ULL);
    CHECK(elapsed < 50000000ULL);

    /* Host builds are expected to reject QNX-only calls with ENOTSUP. */
    CHECK(moq_qnx_set_realtime(MOQ_QNX_PRIO_NET) != 0);
    CHECK(moq_qnx_last_error() != NULL);

    if (failures) {
        fprintf(stderr, "%d check(s) failed\n", failures);
        return EXIT_FAILURE;
    }
    printf("ok: mono clock advanced %llu ns over a 1 ms busy wait\n",
           (unsigned long long)elapsed);
    return EXIT_SUCCESS;
}
