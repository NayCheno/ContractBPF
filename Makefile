.PHONY: bootstrap kernel sched-ext sched-boost bpf userspace kselftest qemu-smoke qemu-sched qemu-sched-gate qemu-mm-hook qemu-contractd qemu-conflict qemu-recovery qemu-experiment-matrix qemu-memcached qemu-memcached-matrix experiments memcached-experiments figures clean

bootstrap:
	./kernel/scripts/fetch-linux.sh
	./kernel/scripts/configure-kernel.sh
	./qemu/rootfs/build-rootfs.sh

kernel:
	./kernel/scripts/apply-patches.sh
	./kernel/scripts/build-kernel.sh

sched-ext:
	mkdir -p build/scx
	$(MAKE) -C build/linux/tools/sched_ext O=$(CURDIR)/build/scx LLVM=1 scx_simple

sched-boost:
	mkdir -p build/scx
	$(MAKE) -C build/linux/tools/sched_ext O=$(CURDIR)/build/scx LLVM=1 scx_contract_boost

bpf:
	$(MAKE) -C bpf

userspace:
	cargo build --manifest-path userspace/contractd/Cargo.toml
	cargo build --manifest-path userspace/contractctl/Cargo.toml
	cargo build --manifest-path userspace/libcontract/Cargo.toml

kselftest:
	./kernel/scripts/build-selftests.sh
	./qemu/rootfs/build-contractbpf-selftest-rootfs.sh
	./qemu/run/run-kselftest.sh

qemu-smoke:
	./qemu/run/run-smoke.sh

qemu-sched:
	$(MAKE) sched-ext
	./qemu/rootfs/build-sched-rootfs.sh
	./qemu/run/run-sched-ext.sh

qemu-sched-gate:
	$(MAKE) sched-boost
	./qemu/rootfs/build-sched-gate-rootfs.sh
	./qemu/run/run-sched-gate.sh

qemu-mm-hook:
	./qemu/rootfs/build-mm-hook-rootfs.sh
	./qemu/run/run-mm-hook.sh

qemu-contractd: userspace
	./qemu/rootfs/build-contractd-rootfs.sh
	./qemu/run/run-contractd.sh

qemu-conflict:
	$(MAKE) sched-boost
	$(MAKE) -C workloads/synthetic_phase_service
	./qemu/rootfs/build-conflict-rootfs.sh
	./qemu/run/run-conflict.sh

qemu-recovery:
	$(MAKE) sched-boost
	$(MAKE) -C workloads/synthetic_phase_service
	./qemu/rootfs/build-conflict-rootfs.sh
	./qemu/run/run-recovery.sh

qemu-experiment-matrix:
	$(MAKE) sched-boost
	$(MAKE) -C workloads/synthetic_phase_service
	./qemu/rootfs/build-experiment-matrix-rootfs.sh
	./qemu/run/run-experiment-matrix.sh

qemu-memcached:
	$(MAKE) -C workloads/memcached
	./qemu/rootfs/build-memcached-rootfs.sh
	./qemu/run/run-memcached.sh

qemu-memcached-matrix:
	$(MAKE) sched-boost
	$(MAKE) -C workloads/memcached
	./qemu/rootfs/build-memcached-matrix-rootfs.sh
	./qemu/run/run-memcached-matrix.sh

experiments:
	$(MAKE) sched-boost
	$(MAKE) -C workloads/synthetic_phase_service
	./qemu/rootfs/build-experiment-matrix-rootfs.sh
	python3 experiments/runners/run_matrix.py --config experiments/configs

memcached-experiments:
	$(MAKE) sched-boost
	$(MAKE) -C workloads/memcached
	./qemu/rootfs/build-memcached-matrix-rootfs.sh
	python3 experiments/runners/run_memcached_matrix.py --config experiments/configs

figures:
	python3 experiments/analysis/plot_feedback_timeline.py
	python3 experiments/analysis/plot_tail_latency.py
	python3 experiments/analysis/plot_recovery.py
	python3 experiments/analysis/plot_ablation.py
	python3 experiments/analysis/plot_overhead.py

clean:
	./kernel/scripts/clean-kernel.sh
