/* SPDX-License-Identifier: GPL-2.0 */
#include <linux/bpf.h>
#include <bpf/bpf_helpers.h>
#include "../include/contract_mm.bpf.h"

SEC("syscall")
int contract_conservative_noop_decide(void *ctx)
{
    (void)ctx;
    return CONTRACT_MM_NO_OP;
}

char LICENSE[] SEC("license") = "GPL";
