#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <linux/mempolicy.h>
#include <sched.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/time.h>
#include <sys/types.h>
#include <time.h>
#include <unistd.h>

#ifndef MPOL_PREFERRED
#define MPOL_PREFERRED 1
#endif

#ifndef MPOL_BIND
#define MPOL_BIND 2
#endif

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

static uint64_t now_us(void)
{
    struct timespec ts;

    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000000ULL + (uint64_t)ts.tv_nsec / 1000ULL;
}

static void bind_cpu0(void)
{
    cpu_set_t set;

    CPU_ZERO(&set);
    CPU_SET(0, &set);
    if (sched_setaffinity(0, sizeof(set), &set))
        fprintf(stderr, "memory_pressure: sched_setaffinity failed: %s\n",
                strerror(errno));
}

static void prefer_node0(void)
{
    const char *policy = getenv("CONTRACTBPF_PRESSURE_MEMPOLICY");
    unsigned long mask = 1UL;
    int mode = MPOL_PREFERRED;

    if (policy && strcmp(policy, "bind") == 0)
        mode = MPOL_BIND;

    if (syscall(SYS_set_mempolicy, mode, &mask, 8 * sizeof(mask))) {
        fprintf(stderr, "memory_pressure: set_mempolicy node0 failed: %s\n",
                strerror(errno));
    } else {
        printf("MEMORY_PRESSURE_MEMPOLICY=%s_node0\n",
               mode == MPOL_BIND ? "bind" : "preferred");
    }
}

static void touch_range(unsigned char *buf, size_t len, unsigned int salt)
{
    for (size_t off = 0; off < len; off += 4096)
        buf[off] = (unsigned char)(buf[off] + salt + 1);
}

static int write_file_pages(int fd, size_t len, unsigned int salt)
{
    unsigned char page[4096];

    memset(page, (int)(salt + 1), sizeof(page));
    for (size_t off = 0; off < len; off += sizeof(page)) {
        if (pwrite(fd, page, sizeof(page), (off_t)off) != (ssize_t)sizeof(page)) {
            fprintf(stderr, "memory_pressure: pwrite failed at %zu: %s\n", off,
                    strerror(errno));
            return -1;
        }
    }
    return 0;
}

static uint64_t sample_read_range(volatile unsigned char *buf, size_t len)
{
    uint64_t start = now_us();
    uint64_t sum = 0;

    for (size_t off = 0; off < len; off += 4096)
        sum += buf[off];

    printf("MEMORY_PRESSURE_READ_SUM=%llu\n", (unsigned long long)sum);
    return now_us() - start;
}

static uint64_t sample_read_file(int fd, size_t len)
{
    unsigned char page[4096];
    uint64_t start = now_us();
    uint64_t sum = 0;

    for (size_t off = 0; off < len; off += sizeof(page)) {
        ssize_t got = pread(fd, page, sizeof(page), (off_t)off);

        if (got <= 0) {
            fprintf(stderr, "memory_pressure: pread failed at %zu: %s\n", off,
                    got < 0 ? strerror(errno) : "short read");
            break;
        }
        sum += page[0];
    }

    printf("MEMORY_PRESSURE_READ_SUM=%llu\n", (unsigned long long)sum);
    return now_us() - start;
}

static int ensure_file(const char *path, size_t len)
{
    int fd = open(path, O_RDWR | O_CREAT, 0644);

    if (fd < 0) {
        fprintf(stderr, "memory_pressure: open %s failed: %s\n", path,
                strerror(errno));
        return -1;
    }
    if (ftruncate(fd, (off_t)len)) {
        fprintf(stderr, "memory_pressure: ftruncate %s failed: %s\n", path,
                strerror(errno));
        close(fd);
        return -1;
    }
    return fd;
}

int main(int argc, char **argv)
{
    const char *path = argc > 1 ? argv[1] : "/tmp/contractbpf-pressure-file.bin";
    long file_mb = argc > 2 ? parse_long(argv[2], 192) : 192;
    long pressure_mb = argc > 3 ? parse_long(argv[3], 512) : 512;
    long iterations = argc > 4 ? parse_long(argv[4], 4) : 4;
    size_t file_len = (size_t)file_mb * 1024U * 1024U;
    size_t pressure_len = (size_t)pressure_mb * 1024U * 1024U;
    unsigned char *file_map = NULL;
    unsigned char *pressure;
    int fd;

    setvbuf(stdout, NULL, _IONBF, 0);
    setvbuf(stderr, NULL, _IONBF, 0);

    bind_cpu0();
    prefer_node0();

    fd = ensure_file(path, file_len);
    if (fd < 0)
        return 1;

    file_map = mmap(NULL, file_len, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (file_map == MAP_FAILED) {
        fprintf(stderr, "memory_pressure: mmap file unavailable, using pread/pwrite: %s\n",
                strerror(errno));
        file_map = NULL;
    }

    pressure = mmap(NULL, pressure_len, PROT_READ | PROT_WRITE,
                    MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (pressure == MAP_FAILED) {
        fprintf(stderr, "memory_pressure: mmap pressure failed: %s\n",
                strerror(errno));
        if (file_map)
            munmap(file_map, file_len);
        close(fd);
        return 1;
    }

    printf("MEMORY_PRESSURE_START file=%s file_mb=%ld pressure_mb=%ld iterations=%ld\n",
           path, file_mb, pressure_mb, iterations);

    if (file_map) {
        touch_range(file_map, file_len, 0);
        puts("MEMORY_PRESSURE_FILE_TOUCHED");
        if (msync(file_map, file_len, MS_SYNC))
            fprintf(stderr, "memory_pressure: msync warning: %s\n", strerror(errno));
    } else if (write_file_pages(fd, file_len, 0)) {
        munmap(pressure, pressure_len);
        close(fd);
        return 1;
    } else if (fsync(fd)) {
        fprintf(stderr, "memory_pressure: fsync warning: %s\n", strerror(errno));
    }
    if (!file_map)
        puts("MEMORY_PRESSURE_FILE_TOUCHED");

    for (long i = 0; i < iterations; i++) {
        uint64_t latency_us;

        touch_range(pressure, pressure_len, (unsigned int)i);
        printf("MEMORY_PRESSURE_PRESSURE_TOUCHED iteration=%ld\n", i);
        if (file_map)
            latency_us = sample_read_range(file_map, file_len);
        else
            latency_us = sample_read_file(fd, file_len);
        printf("LATENCY_SAMPLE_US=%llu\n", (unsigned long long)latency_us);
        printf("MEMORY_PRESSURE_ITERATION=%ld\n", i);
        usleep(50000);
    }

    munmap(pressure, pressure_len);
    if (file_map)
        munmap(file_map, file_len);
    close(fd);

    puts("MEMORY_PRESSURE_OK");
    return 0;
}

