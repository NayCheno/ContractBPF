/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Source mirror of the intentionally aggressive sched_ext policy used by the
 * QEMU M4 validation. The buildable copy is carried in the pinned kernel
 * tools/sched_ext patch so it can reuse the kernel's scx build system.
 */
#include <scx/common.bpf.h>

char _license[] SEC("license") = "GPL";

#define CONTRACT_BOOST_SLICE_NS (200LLU * 1000 * 1000)

UEI_DEFINE(uei);

s32 BPF_STRUCT_OPS(contract_boost_select_cpu, struct task_struct *p,
		   s32 prev_cpu, u64 wake_flags)
{
	bool is_idle = false;
	s32 cpu;

	cpu = scx_bpf_select_cpu_dfl(p, prev_cpu, wake_flags, &is_idle);
	if (is_idle)
		scx_bpf_dispatch(p, SCX_DSQ_LOCAL, CONTRACT_BOOST_SLICE_NS, 0);

	return cpu;
}

void BPF_STRUCT_OPS(contract_boost_enqueue, struct task_struct *p, u64 enq_flags)
{
	scx_bpf_dispatch(p, SCX_DSQ_GLOBAL, CONTRACT_BOOST_SLICE_NS, enq_flags);
}

void BPF_STRUCT_OPS(contract_boost_exit, struct scx_exit_info *ei)
{
	UEI_RECORD(uei, ei);
}

SCX_OPS_DEFINE(contract_boost_ops,
	       .select_cpu	= (void *)contract_boost_select_cpu,
	       .enqueue		= (void *)contract_boost_enqueue,
	       .exit		= (void *)contract_boost_exit,
	       .name		= "contract_boost");
