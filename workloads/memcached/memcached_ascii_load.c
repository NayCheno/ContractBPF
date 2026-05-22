#include <arpa/inet.h>
#include <errno.h>
#include <netinet/in.h>
#include <net/if.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/ioctl.h>
#include <sys/time.h>
#include <time.h>
#include <unistd.h>

static uint64_t now_us(void)
{
    struct timespec ts;

    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000000ULL + (uint64_t)ts.tv_nsec / 1000ULL;
}

static int connect_loopback(int port)
{
    struct sockaddr_in addr;
    int fd = socket(AF_INET, SOCK_STREAM, 0);

    if (fd < 0)
        return -1;

    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons((uint16_t)port);
    if (inet_pton(AF_INET, "127.0.0.1", &addr.sin_addr) != 1) {
        close(fd);
        return -1;
    }

    if (connect(fd, (struct sockaddr *)&addr, sizeof(addr)) != 0) {
        close(fd);
        return -1;
    }

    return fd;
}

static void bring_loopback_up(void)
{
    struct ifreq ifr;
    int fd = socket(AF_INET, SOCK_DGRAM, 0);

    if (fd < 0)
        return;

    memset(&ifr, 0, sizeof(ifr));
    snprintf(ifr.ifr_name, sizeof(ifr.ifr_name), "lo");
    if (ioctl(fd, SIOCGIFFLAGS, &ifr) == 0) {
        ifr.ifr_flags |= IFF_UP | IFF_RUNNING;
        (void)ioctl(fd, SIOCSIFFLAGS, &ifr);
    }

    close(fd);
}

static int write_all(int fd, const char *buf, size_t len)
{
    while (len) {
        ssize_t n = write(fd, buf, len);

        if (n < 0 && errno == EINTR)
            continue;
        if (n <= 0)
            return -1;
        buf += n;
        len -= (size_t)n;
    }
    return 0;
}

static int read_until(int fd, const char *needle)
{
    char buf[4096];
    size_t needle_len = strlen(needle);
    size_t matched = 0;

    for (;;) {
        ssize_t n = read(fd, buf, sizeof(buf));

        if (n < 0 && errno == EINTR)
            continue;
        if (n <= 0)
            return -1;
        for (ssize_t i = 0; i < n; i++) {
            if (buf[i] == needle[matched]) {
                matched++;
                if (matched == needle_len)
                    return 0;
            } else {
                matched = buf[i] == needle[0] ? 1 : 0;
            }
        }
    }
}

static int request(int fd, const char *payload, const char *needle, uint64_t *latency_us)
{
    uint64_t start = now_us();

    if (write_all(fd, payload, strlen(payload)) != 0)
        return -1;
    if (read_until(fd, needle) != 0)
        return -1;

    *latency_us = now_us() - start;
    return 0;
}

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

int main(int argc, char **argv)
{
    int port = (int)(argc > 1 ? parse_long(argv[1], 11211) : 11211);
    long ops = argc > 2 ? parse_long(argv[2], 100) : 100;
    long value_bytes = argc > 3 ? parse_long(argv[3], 16) : 16;
    int fd = connect_loopback(port);
    uint64_t total = 0;
    uint64_t max = 0;
    long samples = 0;
    char *value;

    if (fd < 0) {
        bring_loopback_up();
        fd = connect_loopback(port);
    }

    if (fd < 0) {
        perror("connect memcached");
        return 1;
    }

    {
        struct timeval timeout = {
            .tv_sec = 5,
            .tv_usec = 0,
        };

        (void)setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
        (void)setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));
    }

    if (value_bytes > 1024 * 1024)
        value_bytes = 1024 * 1024;
    value = calloc((size_t)value_bytes + 1, 1);
    if (!value) {
        perror("calloc");
        close(fd);
        return 1;
    }
    memset(value, 'x', (size_t)value_bytes);

    for (long i = 0; i < ops; i++) {
        size_t set_len = (size_t)value_bytes + 128;
        char *set_cmd = malloc(set_len);
        char get_cmd[128];
        uint64_t latency;

        if (!set_cmd) {
            perror("malloc");
            free(value);
            close(fd);
            return 1;
        }

        snprintf(set_cmd, set_len,
                 "set contractbpf:%ld 0 30 %ld\r\n%s\r\n", i, value_bytes, value);
        snprintf(get_cmd, sizeof(get_cmd), "get contractbpf:%ld\r\n", i);

        if (request(fd, set_cmd, "STORED\r\n", &latency) != 0) {
            perror("set");
            free(set_cmd);
            free(value);
            close(fd);
            return 1;
        }
        free(set_cmd);
        printf("LATENCY_SAMPLE_US=%llu\n", (unsigned long long)latency);
        total += latency;
        if (latency > max)
            max = latency;
        samples++;

        if (request(fd, get_cmd, "END\r\n", &latency) != 0) {
            perror("get");
            free(value);
            close(fd);
            return 1;
        }
        printf("LATENCY_SAMPLE_US=%llu\n", (unsigned long long)latency);
        total += latency;
        if (latency > max)
            max = latency;
        samples++;
    }

    free(value);
    close(fd);
    printf("ops=%ld\n", samples);
    printf("avg_latency_us=%llu\n",
           samples ? (unsigned long long)(total / (uint64_t)samples) : 0ULL);
    printf("max_latency_us=%llu\n", (unsigned long long)max);
    puts("MEMCACHED_LOAD_OK");
    return 0;
}
