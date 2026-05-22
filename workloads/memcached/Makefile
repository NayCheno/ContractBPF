CC ?= cc
CFLAGS ?= -O2 -Wall -Wextra

.PHONY: all clean

all: memcached_ascii_load

memcached_ascii_load: memcached_ascii_load.c
	$(CC) $(CFLAGS) -o $@ $<

clean:
	rm -f memcached_ascii_load
