/* SPDX-License-Identifier: GPL-2.0 */
#include <linux/bpf.h>
#include <bpf/bpf_helpers.h>
#include "../include/contract_mm.bpf.h"

SEC("syscall")
int contract_phase_paging_decide(void *ctx)
{
    const struct contract_mm_region_state *state = contract_mm_state_get();

    (void)ctx;
    if (!state)
        return CONTRACT_MM_NO_OP;

    if (state->recent_refaults || state->recent_major_faults)
        return CONTRACT_MM_KEEP;
    if (state->hotness < 25 && state->pages)
        return CONTRACT_MM_DEMOTE;
    if (state->hotness < 50)
        return CONTRACT_MM_RECLAIM_HINT;
    return CONTRACT_MM_KEEP;
}

char LICENSE[] SEC("license") = "GPL";
