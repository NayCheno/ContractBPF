CC ?= cc
CFLAGS ?= -O2 -Wall -Wextra

.PHONY: all clean

all: pressure

pressure: pressure.c
	$(CC) $(CFLAGS) -o $@ $<

clean:
	rm -f pressure

