.PHONY: all clean

CC ?= cc
OUT_DIR ?= ../build/bpf
MM_POLICIES := bad_demote phase_paging conservative_noop_paging
MM_OBJECTS := $(addprefix $(OUT_DIR)/,$(addsuffix .o,$(MM_POLICIES)))

all: $(OUT_DIR)/scx_contract_latency $(MM_OBJECTS)

$(OUT_DIR)/scx_contract_latency: sched_ext/scx_contract_latency.c
	mkdir -p $(OUT_DIR)
	$(CC) -Wall -Wextra -O2 -o $@ $<

$(OUT_DIR)/%.o: mm/%.bpf.c include/contract_mm.bpf.h
	mkdir -p $(OUT_DIR)
	$(CC) -Wall -Wextra -O2 -c -o $@ $<

clean:
	rm -rf $(OUT_DIR) sched_ext/scx_contract_latency
