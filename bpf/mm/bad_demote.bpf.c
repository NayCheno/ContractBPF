/* SPDX-License-Identifier: GPL-2.0 */
#include <linux/bpf.h>
#include <bpf/bpf_helpers.h>
#include "../include/contract_mm.bpf.h"

SEC("syscall")
int contract_bad_demote_decide(void *ctx)
{
    const struct contract_mm_region_state *state = contract_mm_state_get();

    (void)ctx;
    if (!state)
        return CONTRACT_MM_NO_OP;
    return CONTRACT_MM_DEMOTE;
}

char LICENSE[] SEC("license") = "GPL";
