/* SPDX-License-Identifier: GPL-2.0 */
#include "../include/contract_mm.bpf.h"

/*
 * Intentionally harmful M5 policy model. The current kernel-side M5 hook
 * validates decisions through debugfs/QEMU; this source documents the bad
 * policy shape that later BPF loading will replace.
 */
int contract_bad_demote_decide(const struct contract_mm_region_state *state)
{
    (void)state;
    return CONTRACT_MM_DEMOTE;
}
