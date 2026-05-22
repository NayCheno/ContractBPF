#ifndef CONTRACT_MM_BPF_H
#define CONTRACT_MM_BPF_H

enum contract_mm_decision {
    CONTRACT_MM_KEEP = 0,
    CONTRACT_MM_DEMOTE = 1,
    CONTRACT_MM_RECLAIM_HINT = 2,
    CONTRACT_MM_NO_OP = 3,
};

struct contract_mm_region_state {
    unsigned long long region_id;
    unsigned long long pages;
    unsigned long long recent_refaults;
    unsigned long long recent_major_faults;
    unsigned int hotness;
    unsigned int flags;
};

#endif
