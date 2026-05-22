CC ?= cc
CFLAGS ?= -O2 -Wall -Wextra

.PHONY: all clean

all: burn

burn: burn.c
	$(CC) $(CFLAGS) -o $@ $<

clean:
	rm -f burn

