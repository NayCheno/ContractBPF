CC ?= cc
CFLAGS ?= -O2 -Wall -Wextra

.PHONY: all clean

all: synthetic_phase_service

synthetic_phase_service: src/main.c
	$(CC) $(CFLAGS) -o $@ $<

clean:
	rm -f synthetic_phase_service

