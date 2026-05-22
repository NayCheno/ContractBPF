// SPDX-License-Identifier: GPL-2.0
#include <bpf/bpf.h>
#include <bpf/libbpf.h>
#include <errno.h>
#include <fcntl.h>
#include <libgen.h>
#include <linux/bpf.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/resource.h>
#include <unistd.h>

#include "../include/contract_mm.bpf.h"

#define CONTRACTBPF_IOC_MAGIC 0xcb
#define CONTRACTBPF_SUBSYS_MM 2

struct contract_ioctl_scope {
    uint32_t scope_type;
    uint32_t reserved;
    uint64_t primary_id;
    uint64_t secondary_id;
};

struct contract_ioctl_gate {
    uint32_t subsystem;
    uint32_t enabled;
    uint32_t reserved;
    uint32_t reserved2;
};

struct contract_ioctl_mm_bpf_policy {
    int32_t prog_fd;
    int32_t state_map_fd;
    uint64_t policy_id;
    uint32_t registered;
    uint32_t reserved;
};

struct contract_ioctl_mm_test_hook {
    uint32_t pages;
    uint32_t decision;
    uint32_t allowed;
    uint32_t reserved;
    struct contract_ioctl_scope scope;
};

#define CONTRACTBPF_IOC_SET_GATE \
    _IOW(CONTRACTBPF_IOC_MAGIC, 5, struct contract_ioctl_gate)
#define CONTRACTBPF_IOC_SET_MM_BPF_POLICY \
    _IOWR(CONTRACTBPF_IOC_MAGIC, 6, struct contract_ioctl_mm_bpf_policy)
#define CONTRACTBPF_IOC_MM_TEST_HOOK \
    _IOWR(CONTRACTBPF_IOC_MAGIC, 7, struct contract_ioctl_mm_test_hook)

static const char *decision_name(unsigned int decision)
{
    switch (decision) {
    case CONTRACT_MM_KEEP:
        return "keep";
    case CONTRACT_MM_DEMOTE:
        return "demote";
    case CONTRACT_MM_RECLAIM_HINT:
        return "reclaim_hint";
    case CONTRACT_MM_NO_OP:
        return "no_op";
    default:
        return "unknown";
    }
}

static int expected_decision(const char *policy, const char *case_name)
{
    if (strstr(policy, "bad_demote"))
        return CONTRACT_MM_DEMOTE;
    if (strstr(policy, "conservative_noop"))
        return CONTRACT_MM_NO_OP;
    if (strstr(policy, "phase_paging")) {
        if (!strcmp(case_name, "cold"))
            return CONTRACT_MM_DEMOTE;
        if (!strcmp(case_name, "refault"))
            return CONTRACT_MM_KEEP;
        if (!strcmp(case_name, "warm"))
            return CONTRACT_MM_RECLAIM_HINT;
    }
    return -1;
}

static int run_case(int prog_fd, int map_fd, const char *policy,
                    const char *case_name,
                    struct contract_mm_region_state state)
{
    unsigned int key = 0;
    int err;
    LIBBPF_OPTS(bpf_test_run_opts, opts);

    err = bpf_map_update_elem(map_fd, &key, &state, BPF_ANY);
    if (err) {
        fprintf(stderr, "map_update failed for %s: %s\n", case_name,
                strerror(errno));
        return 1;
    }

    err = bpf_prog_test_run_opts(prog_fd, &opts);
    if (err) {
        fprintf(stderr, "BPF_PROG_RUN failed for %s: %s\n", case_name,
                strerror(errno));
        return 1;
    }

    printf("decision policy=%s case=%s value=%s raw=%u pages=%u hotness=%u refaults=%u major_faults=%u\n",
           policy, case_name, decision_name(opts.retval), opts.retval,
           state.pages, state.hotness, state.recent_refaults,
           state.recent_major_faults);

    err = expected_decision(policy, case_name);
    if (err >= 0 && opts.retval != (unsigned int)err) {
        fprintf(stderr, "unexpected decision for %s/%s: got %s expected %s\n",
                policy, case_name, decision_name(opts.retval),
                decision_name(err));
        return 1;
    }
    return 0;
}

static int run_live_hook_case(int prog_fd, int map_fd, const char *policy)
{
    struct contract_ioctl_gate gate = {
        .subsystem = CONTRACTBPF_SUBSYS_MM,
        .enabled = 1,
    };
    struct contract_ioctl_mm_bpf_policy kernel_policy = {
        .prog_fd = prog_fd,
        .state_map_fd = map_fd,
    };
    struct contract_ioctl_mm_test_hook hook = {
        .pages = 1,
    };
    int expected = expected_decision(policy, "cold");
    int fd = open("/dev/contractbpf", O_RDWR | O_CLOEXEC);

    if (fd < 0) {
        fprintf(stderr, "open /dev/contractbpf failed: %s\n", strerror(errno));
        return 1;
    }

    if (ioctl(fd, CONTRACTBPF_IOC_SET_GATE, &gate)) {
        fprintf(stderr, "CONTRACTBPF_IOC_SET_GATE failed: %s\n", strerror(errno));
        close(fd);
        return 1;
    }

    if (ioctl(fd, CONTRACTBPF_IOC_SET_MM_BPF_POLICY, &kernel_policy)) {
        fprintf(stderr, "CONTRACTBPF_IOC_SET_MM_BPF_POLICY failed: %s\n",
                strerror(errno));
        close(fd);
        return 1;
    }

    if (ioctl(fd, CONTRACTBPF_IOC_MM_TEST_HOOK, &hook)) {
        fprintf(stderr, "CONTRACTBPF_IOC_MM_TEST_HOOK failed: %s\n",
                strerror(errno));
        close(fd);
        return 1;
    }

    close(fd);

    printf("CONTRACTBPF_MM_BPF_REGISTERED policy=%s kernel_policy_id=%llu\n",
           policy, (unsigned long long)kernel_policy.policy_id);
    printf("live_hook policy=%s value=%s raw=%u allowed=%u scope=%u:%llu:%llu\n",
           policy, decision_name(hook.decision), hook.decision, hook.allowed,
           hook.scope.scope_type, (unsigned long long)hook.scope.primary_id,
           (unsigned long long)hook.scope.secondary_id);

    if (expected >= 0 && hook.decision != (uint32_t)expected) {
        fprintf(stderr, "unexpected live hook decision for %s: got %s expected %s\n",
                policy, decision_name(hook.decision), decision_name(expected));
        return 1;
    }

    if (expected == CONTRACT_MM_DEMOTE && !hook.allowed) {
        fprintf(stderr, "live hook unexpectedly denied demotion for %s\n", policy);
        return 1;
    }
    if (expected != CONTRACT_MM_DEMOTE && hook.allowed) {
        fprintf(stderr, "live hook unexpectedly allowed demotion for %s\n", policy);
        return 1;
    }

    printf("CONTRACTBPF_MM_BPF_LIVE_HOOK_OK policy=%s\n", policy);
    return 0;
}

int main(int argc, char **argv)
{
    struct bpf_object *obj = NULL;
    struct bpf_program *prog = NULL;
    struct bpf_map *map = NULL;
    const char *path;
    char *path_copy = NULL;
    const char *policy;
    int prog_fd, map_fd;
    struct rlimit rlim = {
        .rlim_cur = RLIM_INFINITY,
        .rlim_max = RLIM_INFINITY,
    };
    int ret = 1;

    if (argc != 2) {
        fprintf(stderr, "usage: %s POLICY.bpf.o\n", argv[0]);
        return 2;
    }

    path = argv[1];
    path_copy = strdup(path);
    if (!path_copy) {
        perror("strdup");
        return 1;
    }
    policy = basename(path_copy);

    (void)setrlimit(RLIMIT_MEMLOCK, &rlim);
    libbpf_set_strict_mode(LIBBPF_STRICT_ALL);

    obj = bpf_object__open_file(path, NULL);
    if (!obj) {
        fprintf(stderr, "failed to open BPF object: %s\n", path);
        goto out;
    }
    if (bpf_object__load(obj)) {
        fprintf(stderr, "failed to load BPF object: %s\n", path);
        goto out;
    }

    bpf_object__for_each_program(prog, obj)
        break;
    if (!prog) {
        fprintf(stderr, "no BPF program found in %s\n", path);
        goto out;
    }

    map = bpf_object__find_map_by_name(obj, "contract_mm_state");
    if (!map) {
        fprintf(stderr, "contract_mm_state map missing in %s\n", path);
        goto out;
    }

    prog_fd = bpf_program__fd(prog);
    map_fd = bpf_map__fd(map);
    if (prog_fd < 0 || map_fd < 0) {
        fprintf(stderr, "invalid BPF fd: prog=%d map=%d\n", prog_fd, map_fd);
        goto out;
    }

    printf("CONTRACTBPF_MM_BPF_LOADED policy=%s program=%s prog_fd=%d map_fd=%d\n",
           policy, bpf_program__name(prog), prog_fd, map_fd);

    ret = 0;
    ret |= run_case(prog_fd, map_fd, policy, "cold",
                    (struct contract_mm_region_state){
                        .cgroup_id = 24,
                        .memcg_id = 24,
                        .region_id = 1,
                        .numa_node = 0,
                        .pages = 16,
                        .hotness = 10,
                    });
    ret |= run_case(prog_fd, map_fd, policy, "refault",
                    (struct contract_mm_region_state){
                        .cgroup_id = 24,
                        .memcg_id = 24,
                        .region_id = 2,
                        .numa_node = 0,
                        .pages = 16,
                        .hotness = 10,
                        .recent_refaults = 4,
                    });
    ret |= run_case(prog_fd, map_fd, policy, "warm",
                    (struct contract_mm_region_state){
                        .cgroup_id = 24,
                        .memcg_id = 24,
                        .region_id = 3,
                        .numa_node = 0,
                        .pages = 16,
                        .hotness = 40,
                    });
    ret |= run_live_hook_case(prog_fd, map_fd, policy);

    if (!ret)
        printf("CONTRACTBPF_MM_BPF_POLICY_OK policy=%s\n", policy);

out:
    bpf_object__close(obj);
    free(path_copy);
    return ret;
}
