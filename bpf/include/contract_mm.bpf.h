#ifndef CONTRACT_MM_BPF_H
#define CONTRACT_MM_BPF_H

enum contract_mm_decision {
    CONTRACT_MM_KEEP = 0,
    CONTRACT_MM_DEMOTE = 1,
    CONTRACT_MM_RECLAIM_HINT = 2,
    CONTRACT_MM_NO_OP = 3,
};

struct contract_mm_region_state {
    unsigned long long cgroup_id;
    unsigned long long memcg_id;
    unsigned long long region_id;
    unsigned int numa_node;
    unsigned int pages;
    unsigned int hotness;
    unsigned int recent_refaults;
    unsigned int recent_major_faults;
    unsigned long long recent_fault_latency_us;
    unsigned int flags;
    unsigned int reserved;
};

#ifdef __BPF__
struct {
    __uint(type, BPF_MAP_TYPE_ARRAY);
    __uint(max_entries, 1);
    __uint(map_flags, BPF_F_RDONLY_PROG);
    __type(key, unsigned int);
    __type(value, struct contract_mm_region_state);
} contract_mm_state SEC(".maps");

static __always_inline const struct contract_mm_region_state *contract_mm_state_get(void)
{
    unsigned int key = 0;

    return bpf_map_lookup_elem(&contract_mm_state, &key);
}
#endif

#endif
