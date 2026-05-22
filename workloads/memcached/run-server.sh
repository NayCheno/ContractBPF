#!/usr/bin/env bash
set -euo pipefail

MEMCACHED_BIN="${MEMCACHED_BIN:-memcached}"
MEMCACHED_HOST="${MEMCACHED_HOST:-127.0.0.1}"
MEMCACHED_PORT="${MEMCACHED_PORT:-11211}"
MEMCACHED_MEMORY_MB="${MEMCACHED_MEMORY_MB:-64}"
MEMCACHED_USER="${MEMCACHED_USER:-}"

if ! command -v "$MEMCACHED_BIN" >/dev/null 2>&1; then
    echo "ERROR: memcached binary not found; set MEMCACHED_BIN or install memcached" >&2
    exit 77
fi

args=("$MEMCACHED_BIN" -l "$MEMCACHED_HOST" -p "$MEMCACHED_PORT" -m "$MEMCACHED_MEMORY_MB")
if [ -n "$MEMCACHED_USER" ]; then
    args+=(-u "$MEMCACHED_USER")
fi

printf 'Starting memcached:'
printf ' %q' "${args[@]}"
printf '\n'
exec "${args[@]}"
