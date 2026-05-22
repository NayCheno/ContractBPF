# Acceptance Gate Audit

Timestamp UTC: 20260522T190721Z
Complete: False

| Gate | Status | Missing |
|---|---|---|
| P0 reproduce current artifact | complete |  |
| P1 remove debugfs final control path | complete |  |
| P2 real policy identity | complete |  |
| P3 real scope mapping | complete |  |
| P4 real BPF paging path | complete |  |
| P5 natural scheduler-paging conflict | partial | native non-QEMU memcached bars missing or failed<br>experiments/results/processed/native_memcached_bars.csv is missing |
| P6 bounded degradation recovery | partial | native non-QEMU recovery bars missing or failed<br>experiments/results/processed/native_memcached_bars.csv is missing |
| P7 overhead and scalability | complete |  |
| P8 paper evidence integrity | partial | final paper audit requires native non-QEMU evidence |
