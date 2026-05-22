# Workloads

Workloads are introduced after the vanilla kernel and `sched_ext` baseline are reproducible in QEMU.

Current workload classes:

- controlled synthetic phase-changing service for QEMU validation;
- memcached server and ASCII protocol load path, including `make qemu-memcached`
  for a QEMU real-service smoke test;
- Redis;
- memory pressure;
- CPU interference.

The controlled synthetic service is wired into `make experiments`. The
memcached path can run either through `make qemu-memcached` or manually with
`workloads/memcached/run-server.sh` and `workloads/memcached/run-load.sh`.
