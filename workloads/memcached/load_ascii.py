#!/usr/bin/env python3
import argparse
import socket
import statistics
import time


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=11211)
    parser.add_argument("--ops", type=int, default=200)
    parser.add_argument("--value-bytes", type=int, default=128)
    parser.add_argument("--timeout", type=float, default=2.0)
    return parser.parse_args()


def percentile(values, pct):
    if not values:
        return 0
    ordered = sorted(values)
    index = int((pct / 100.0) * (len(ordered) - 1))
    return ordered[index]


def read_until(sock, suffix):
    data = bytearray()
    while not data.endswith(suffix):
        chunk = sock.recv(4096)
        if not chunk:
            raise RuntimeError("memcached connection closed")
        data.extend(chunk)
    return bytes(data)


def request(sock, payload, suffix):
    start = time.monotonic_ns()
    sock.sendall(payload)
    read_until(sock, suffix)
    end = time.monotonic_ns()
    return (end - start) // 1000


def main():
    args = parse_args()
    value = b"x" * args.value_bytes
    latencies = []

    with socket.create_connection((args.host, args.port), timeout=args.timeout) as sock:
        sock.settimeout(args.timeout)
        for idx in range(args.ops):
            key = f"contractbpf:{idx}".encode()
            set_cmd = b"set " + key + b" 0 30 " + str(len(value)).encode() + b"\r\n" + value + b"\r\n"
            get_cmd = b"get " + key + b"\r\n"
            latencies.append(request(sock, set_cmd, b"STORED\r\n"))
            latencies.append(request(sock, get_cmd, b"END\r\n"))

    for sample in latencies:
        print(f"LATENCY_SAMPLE_US={sample}")
    print(f"ops={len(latencies)}")
    print(f"p50_latency_us={int(statistics.median(latencies)) if latencies else 0}")
    print(f"p99_latency_us={percentile(latencies, 99)}")
    print("MEMCACHED_LOAD_OK")


if __name__ == "__main__":
    main()
