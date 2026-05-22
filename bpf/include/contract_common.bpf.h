#ifndef CONTRACT_COMMON_BPF_H
#define CONTRACT_COMMON_BPF_H

enum contract_effect_type {
    CONTRACT_EFFECT_SCHED_BOOST = 0,
    CONTRACT_EFFECT_SCHED_DISPATCH = 1,
    CONTRACT_EFFECT_SCHED_PIN_CPU = 2,
    CONTRACT_EFFECT_MM_DEMOTE_PAGE = 3,
    CONTRACT_EFFECT_MM_RECLAIM_HINT = 4,
    CONTRACT_EFFECT_MM_CLASSIFY_REGION = 5,
};

struct contract_scope_id {
    unsigned int type;
    unsigned long long primary_id;
    unsigned long long secondary_id;
};

#endif
