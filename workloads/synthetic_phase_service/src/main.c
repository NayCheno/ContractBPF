#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

static long parse_long(const char *value, long fallback)
{
    char *end = NULL;
    long parsed;

    if (!value)
        return fallback;

    errno = 0;
    parsed = strtol(value, &end, 10);
    if (errno || end == value || parsed <= 0)
        return fallback;
    return parsed;
}

static void busy_us(long usec)
{
    struct timespec start;
    struct timespec now;
    uint64_t elapsed;

    clock_gettime(CLOCK_MONOTONIC, &start);
    do {
        for (volatile unsigned int i = 0; i < 10000; i++)
            ;
        clock_gettime(CLOCK_MONOTONIC, &now);
        elapsed = (uint64_t)(now.tv_sec - start.tv_sec) * 1000000ULL +
                  (uint64_t)(now.tv_nsec - start.tv_nsec) / 1000ULL;
    } while (elapsed < (uint64_t)usec);
}

static uint64_t elapsed_us(const struct timespec *start, const struct timespec *end)
{
    uint64_t start_us = (uint64_t)start->tv_sec * 1000000ULL +
                        (uint64_t)start->tv_nsec / 1000ULL;
    uint64_t end_us = (uint64_t)end->tv_sec * 1000000ULL +
                      (uint64_t)end->tv_nsec / 1000ULL;

    return end_us >= start_us ? end_us - start_us : 0;
}

int main(int argc, char **argv)
{
    long mb = argc > 1 ? parse_long(argv[1], 16) : 16;
    long phases = argc > 2 ? parse_long(argv[2], 4) : 4;
    size_t len = (size_t)mb * 1024U * 1024U;
    unsigned char *buf = malloc(len);

    if (!buf) {
        fprintf(stderr, "synthetic_phase_service: alloc %ld MiB failed\n", mb);
        return 1;
    }

    printf("synthetic_phase_service: start mb=%ld phases=%ld\n", mb, phases);
    fflush(stdout);

    for (long phase = 0; phase < phases; phase++) {
        struct timespec phase_start;
        struct timespec phase_end;

        clock_gettime(CLOCK_MONOTONIC, &phase_start);
        for (size_t off = 0; off < len; off += 4096)
            buf[off] = (unsigned char)(buf[off] + phase + 1);
        busy_us(50000);
        clock_gettime(CLOCK_MONOTONIC, &phase_end);
        printf("synthetic_phase_service: phase=%ld touched_pages=%zu\n",
               phase, len / 4096);
        printf("LATENCY_SAMPLE_US=%llu\n",
               (unsigned long long)elapsed_us(&phase_start, &phase_end));
        fflush(stdout);
        usleep(25000);
    }

    free(buf);
    puts("SYNTHETIC_PHASE_SERVICE_OK");
    return 0;
}
