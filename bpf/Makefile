.PHONY: all clean

CC ?= cc
CLANG ?= clang
LINUX_DIR ?= ../build/linux
OUT_DIR ?= ../build/bpf
LIBBPF_CFLAGS ?= $(shell pkg-config --cflags libbpf 2>/dev/null)
LIBBPF_LIBS ?= $(shell pkg-config --libs libbpf 2>/dev/null || printf '%s\n' "-lbpf -lelf -lz")
BPF_CFLAGS := -g -O2 -target bpf -D__TARGET_ARCH_x86 -D__BPF__ \
	-I/usr/include \
	-I$(LINUX_DIR)/tools/include/uapi \
	-I$(LINUX_DIR)/tools/include \
	-Iinclude
MM_POLICIES := bad_demote phase_paging conservative_noop_paging
MM_OBJECTS := $(addprefix $(OUT_DIR)/,$(addsuffix .bpf.o,$(MM_POLICIES)))

all: $(OUT_DIR)/scx_contract_latency $(OUT_DIR)/contract_mm_loader $(MM_OBJECTS)

$(OUT_DIR)/scx_contract_latency: sched_ext/scx_contract_latency.c
	mkdir -p $(OUT_DIR)
	$(CC) -Wall -Wextra -O2 -o $@ $<

$(OUT_DIR)/contract_mm_loader: mm/contract_mm_loader.c include/contract_mm.bpf.h
	mkdir -p $(OUT_DIR)
	$(CC) -Wall -Wextra -O2 $(LIBBPF_CFLAGS) -Iinclude -o $@ $< $(LIBBPF_LIBS)

$(OUT_DIR)/%.bpf.o: mm/%.bpf.c include/contract_mm.bpf.h
	mkdir -p $(OUT_DIR)
	$(CLANG) $(BPF_CFLAGS) -c -o $@ $<

clean:
	rm -rf $(OUT_DIR) sched_ext/scx_contract_latency
