/*
 * clock_probe — measure this machine's clock offset against a time reference.
 *
 * The reference is scripts/time_probe_server.py running on another host:
 *
 *     clock_probe <host> [port] [samples]
 *
 * It performs the four-timestamp NTP exchange over a plain HTTP GET:
 *
 *     t1 = now()                     (before the request)
 *     t2 = reference timestamp       (from the body)
 *     t4 = now()                     (after the response)
 *
 *     offset = t2 - (t1 + t4) / 2
 *     error  = (t4 - t1) / 2         (half the round trip)
 *
 * Positive offset means this machine is AHEAD of the reference.
 * The median of the samples is printed, since a single probe can be skewed by
 * scheduling noise.
 */
#define _POSIX_C_SOURCE 200809L

#include <arpa/inet.h>
#include <errno.h>
#include <netdb.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>

static long long now_ms(void) {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return (long long)tv.tv_sec * 1000LL + tv.tv_usec / 1000;
}

/* One probe. Returns 0 on success and fills *offset / *rtt (milliseconds). */
static int probe_once(const char* host, int port, long long* offset, long long* rtt) {
    char portstr[16];
    snprintf(portstr, sizeof(portstr), "%d", port);

    struct sockaddr_in sa;
    memset(&sa, 0, sizeof(sa));
    sa.sin_family = AF_INET;
    sa.sin_port = htons((unsigned short)port);

    /* A literal IPv4 address avoids a resolver round trip (and works on minimal
     * QNX images that have no resolver configured). */
    if (inet_pton(AF_INET, host, &sa.sin_addr) != 1) {
        struct addrinfo hints, *res = NULL;
        memset(&hints, 0, sizeof(hints));
        hints.ai_family = AF_INET;
        hints.ai_socktype = SOCK_STREAM;
        if (getaddrinfo(host, portstr, &hints, &res) != 0 || !res) {
            fprintf(stderr, "resolve failed: %s\n", host);
            return -1;
        }
        memcpy(&sa, res->ai_addr, sizeof(sa));
        freeaddrinfo(res);
    }

    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return -1;

    struct timeval tv = { .tv_sec = 5, .tv_usec = 0 };
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));

    long long t1 = now_ms();
    if (connect(fd, (struct sockaddr*)&sa, sizeof(sa)) != 0) {
        fprintf(stderr, "connect failed: %s\n", strerror(errno));
        close(fd);
        return -1;
    }

    const char* req = "GET /time_plain HTTP/1.0\r\nHost: x\r\nConnection: close\r\n\r\n";
    if (write(fd, req, strlen(req)) < 0) { close(fd); return -1; }

    char buf[2048];
    char acc[4096];
    size_t acclen = 0;
    ssize_t n;
    long long t4 = 0;
    char body[64];
    size_t blen = 0;
    size_t body_off = 0;
    int found = 0;

    memset(acc, 0, sizeof(acc));
    memset(body, 0, sizeof(body));

    while ((n = read(fd, buf, sizeof(buf))) > 0) {
        if (acclen + (size_t)n >= sizeof(acc) - 1) break;
        memcpy(acc + acclen, buf, (size_t)n);
        acclen += (size_t)n;
        acc[acclen] = '\0';
        const char* sep = strstr(acc, "\r\n\r\n");
        if (sep) {
            body_off = (size_t)(sep - acc) + 4;
            found = 1;
            break;              /* the body of a one-line response fits already */
        }
    }
    if (found) {
        t4 = now_ms();
        for (size_t i = body_off; i < acclen && blen < sizeof(body) - 1; i++) {
            if (acc[i] >= '0' && acc[i] <= '9') body[blen++] = acc[i];
        }
    }
    close(fd);
    if (!t4) t4 = now_ms();

    if (blen == 0) {
        fprintf(stderr, "empty response\n");
        return -1;
    }

    long long t2 = atoll(body);
    *offset = t2 - (t1 + t4) / 2;
    *rtt = t4 - t1;
    return 0;
}

static int cmp_ll(const void* a, const void* b) {
    long long x = *(const long long*)a, y = *(const long long*)b;
    return (x > y) - (x < y);
}

int main(int argc, char** argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: %s <host> [port] [samples]\n", argv[0]);
        return 2;
    }
    const char* host = argv[1];
    int port = (argc > 2) ? atoi(argv[2]) : 9001;
    int samples = (argc > 3) ? atoi(argv[3]) : 9;
    if (samples < 1) samples = 1;

    long long offs[64], rtts[64];
    if (samples > 64) samples = 64;

    int ok = 0;
    for (int i = 0; i < samples; i++) {
        long long o = 0, r = 0;
        if (probe_once(host, port, &o, &r) == 0) {
            offs[ok] = o;
            rtts[ok] = r;
            ok++;
        }
        usleep(100 * 1000);
    }
    if (!ok) {
        fprintf(stderr, "no successful probe\n");
        return 1;
    }

    qsort(offs, ok, sizeof(long long), cmp_ll);
    qsort(rtts, ok, sizeof(long long), cmp_ll);

    printf("samples=%d offset_ms_median=%lld rtt_ms_median=%lld\n",
           ok, offs[ok / 2], rtts[ok / 2]);
    printf("%s\n", offs[ok / 2] > 0
           ? "this machine is AHEAD of the reference"
           : "this machine is BEHIND the reference");
    return 0;
}
