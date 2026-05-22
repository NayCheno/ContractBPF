DOCKER_COMPOSE ?= docker compose
DOCKER_SERVICE ?= contractbpf
DOCKER_RUN = $(DOCKER_COMPOSE) run --rm $(DOCKER_SERVICE)
DOCKER_NATIVE_RUN = $(DOCKER_COMPOSE) -f docker-compose.yml -f docker-compose.native.yml run --rm $(DOCKER_SERVICE)

.PHONY: bootstrap kernel sched-ext sched-boost bpf userspace kselftest qemu-smoke qemu-sched qemu-sched-gate qemu-mm-hook qemu-mm-bpf qemu-contractd qemu-conflict qemu-recovery qemu-natural-conflict qemu-natural-recovery qemu-ledger-stress qemu-hotpath-timing qemu-scope-runtime qemu-policy-identity qemu-no-violation-overhead qemu-memcached-natural-bars qemu-mature-gates native-p5p6-preflight native-p5p6-bars native-mature-gates remote-native-mature-gates acceptance-audit acceptance-audit-tests paper-tables qemu-experiment-matrix qemu-memcached qemu-memcached-matrix experiments memcached-experiments figures archive-repro docker-build docker-shell docker-bootstrap docker-smoke docker-full docker-mature-gates docker-native-preflight docker-native-p5p6-bars docker-native-mature-gates docker-remote-native-mature-gates clean

bootstrap:
	./kernel/scripts/fetch-linux.sh
	./qemu/rootfs/build-rootfs.sh

kernel:
	./kernel/scripts/apply-patches.sh
	./kernel/scripts/configure-kernel.sh
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

qemu-sched-gate: userspace
	$(MAKE) sched-boost
	./qemu/rootfs/build-sched-gate-rootfs.sh
	./qemu/run/run-sched-gate.sh

qemu-mm-hook: bpf
	./qemu/rootfs/build-mm-hook-rootfs.sh
	./qemu/run/run-mm-hook.sh
	bash qemu/rootfs/build-mm-bpf-rootfs.sh
	bash qemu/run/run-mm-bpf.sh

qemu-mm-bpf: bpf
	bash qemu/rootfs/build-mm-bpf-rootfs.sh
	bash qemu/run/run-mm-bpf.sh

qemu-contractd: userspace
	./qemu/rootfs/build-contractd-rootfs.sh
	./qemu/run/run-contractd.sh

qemu-conflict: userspace
	$(MAKE) sched-boost
	$(MAKE) -C workloads/synthetic_phase_service
	./qemu/rootfs/build-conflict-rootfs.sh
	./qemu/run/run-conflict.sh

qemu-recovery: userspace
	$(MAKE) sched-boost
	$(MAKE) -C workloads/synthetic_phase_service
	./qemu/rootfs/build-conflict-rootfs.sh
	./qemu/run/run-recovery.sh

qemu-natural-conflict: userspace bpf
	$(MAKE) sched-boost
	$(MAKE) -C workloads/synthetic_phase_service
	$(MAKE) -C workloads/memory_pressure
	bash qemu/rootfs/build-natural-conflict-rootfs.sh
	bash qemu/run/run-natural-conflict.sh

qemu-natural-recovery: userspace bpf
	$(MAKE) sched-boost
	$(MAKE) -C workloads/synthetic_phase_service
	$(MAKE) -C workloads/memory_pressure
	bash qemu/rootfs/build-natural-conflict-rootfs.sh
	CONTRACTBPF_NATURAL_RECOVERY=1 CONTRACTBPF_NATURAL_RUNS=1 bash qemu/run/run-natural-conflict.sh

qemu-ledger-stress: userspace bpf
	$(MAKE) -C workloads/synthetic_phase_service
	$(MAKE) -C workloads/memory_pressure
	bash qemu/rootfs/build-natural-conflict-rootfs.sh
	CONTRACTBPF_LEDGER_STRESS=1 bash qemu/run/run-natural-conflict.sh

qemu-hotpath-timing: userspace bpf
	$(MAKE) -C workloads/synthetic_phase_service
	$(MAKE) -C workloads/memory_pressure
	bash qemu/rootfs/build-natural-conflict-rootfs.sh
	CONTRACTBPF_HOTPATH_TIMING=1 bash qemu/run/run-natural-conflict.sh

qemu-scope-runtime: userspace bpf
	$(MAKE) sched-boost
	$(MAKE) -C workloads/synthetic_phase_service
	$(MAKE) -C workloads/memory_pressure
	bash qemu/rootfs/build-natural-conflict-rootfs.sh
	CONTRACTBPF_SCOPE_RUNTIME=1 bash qemu/run/run-natural-conflict.sh

qemu-policy-identity: userspace bpf
	$(MAKE) sched-ext
	$(MAKE) sched-boost
	$(MAKE) -C workloads/synthetic_phase_service
	bash qemu/rootfs/build-policy-identity-rootfs.sh
	bash qemu/run/run-policy-identity.sh

qemu-no-violation-overhead: userspace
	$(MAKE) sched-boost
	$(MAKE) -C workloads/memcached
	./qemu/rootfs/build-memcached-matrix-rootfs.sh
	python3 experiments/runners/run_no_violation_overhead.py

qemu-memcached-natural-bars: userspace bpf
	$(MAKE) sched-boost
	$(MAKE) -C workloads/memcached
	$(MAKE) -C workloads/memory_pressure
	bash qemu/rootfs/build-memcached-natural-rootfs.sh
	python3 experiments/runners/run_memcached_natural_bars.py

qemu-mature-gates:
	$(MAKE) bootstrap kernel kselftest qemu-smoke qemu-sched qemu-sched-gate qemu-mm-hook qemu-mm-bpf qemu-contractd qemu-conflict qemu-recovery qemu-natural-conflict qemu-natural-recovery qemu-ledger-stress qemu-hotpath-timing qemu-policy-identity qemu-scope-runtime qemu-no-violation-overhead qemu-memcached-natural-bars experiments memcached-experiments paper-tables archive-repro

native-p5p6-preflight: userspace bpf sched-boost
	$(MAKE) -C workloads/memcached
	$(MAKE) -C workloads/memory_pressure
	python3 experiments/runners/run_native_p5p6_preflight.py

native-p5p6-bars: userspace bpf sched-boost
	$(MAKE) -C workloads/memcached
	$(MAKE) -C workloads/memory_pressure
	python3 experiments/runners/run_native_memcached_bars.py

native-mature-gates:
	$(MAKE) native-p5p6-bars
	$(MAKE) paper-tables
	$(MAKE) acceptance-audit
	$(MAKE) archive-repro

remote-native-mature-gates:
	python3 experiments/runners/run_remote_native_mature_gates.py

acceptance-audit:
	python3 experiments/runners/acceptance_gate_audit.py

acceptance-audit-tests:
	python3 -m unittest discover -s experiments/tests

paper-tables:
	python3 experiments/analysis/generate_paper_tables.py

qemu-experiment-matrix: userspace
	$(MAKE) sched-boost
	$(MAKE) -C workloads/synthetic_phase_service
	./qemu/rootfs/build-experiment-matrix-rootfs.sh
	./qemu/run/run-experiment-matrix.sh

qemu-memcached:
	$(MAKE) -C workloads/memcached
	./qemu/rootfs/build-memcached-rootfs.sh
	./qemu/run/run-memcached.sh

qemu-memcached-matrix: userspace
	$(MAKE) sched-boost
	$(MAKE) -C workloads/memcached
	./qemu/rootfs/build-memcached-matrix-rootfs.sh
	./qemu/run/run-memcached-matrix.sh

experiments: userspace
	$(MAKE) sched-boost
	$(MAKE) -C workloads/synthetic_phase_service
	./qemu/rootfs/build-experiment-matrix-rootfs.sh
	python3 experiments/runners/run_matrix.py --config experiments/configs

memcached-experiments: userspace
	$(MAKE) sched-boost
	$(MAKE) -C workloads/memcached
	./qemu/rootfs/build-memcached-matrix-rootfs.sh
	python3 experiments/runners/run_memcached_matrix.py --config experiments/configs
	python3 experiments/runners/archive_repro.py

figures:
	python3 experiments/analysis/plot_feedback_timeline.py
	python3 experiments/analysis/plot_tail_latency.py
	python3 experiments/analysis/plot_recovery.py
	python3 experiments/analysis/plot_ablation.py
	python3 experiments/analysis/plot_overhead.py

archive-repro:
	python3 experiments/runners/archive_repro.py

docker-build:
	$(DOCKER_COMPOSE) build $(DOCKER_SERVICE)

docker-shell:
	$(DOCKER_RUN)

docker-bootstrap:
	$(DOCKER_RUN) make bootstrap

docker-smoke:
	$(DOCKER_RUN) make bootstrap kernel qemu-smoke

docker-full:
	$(DOCKER_RUN) make qemu-mature-gates

docker-mature-gates:
	$(DOCKER_RUN) make qemu-mature-gates

docker-native-preflight:
	$(DOCKER_NATIVE_RUN) make native-p5p6-preflight

docker-native-p5p6-bars:
	$(DOCKER_NATIVE_RUN) make native-p5p6-bars

docker-native-mature-gates:
	$(DOCKER_NATIVE_RUN) make native-mature-gates

docker-remote-native-mature-gates:
	$(DOCKER_RUN) make remote-native-mature-gates

clean:
	./kernel/scripts/clean-kernel.sh
