/* SPDX-License-Identifier: GPL-2.0 */
#include "../include/contract_mm.bpf.h"

int contract_conservative_noop_decide(const struct contract_mm_region_state *state)
{
    (void)state;
    return CONTRACT_MM_NO_OP;
}
