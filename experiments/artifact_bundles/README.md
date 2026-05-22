# Artifact Bundles

`make memcached-experiments` runs the QEMU memcached companion matrix and then
archives the current reproduction evidence into:

```text
artifacts/repro/<timestamp>/
experiments/artifact_bundles/<timestamp>.tar.zst
```

Each bundle contains raw serial logs, processed CSVs, figure inputs/outputs, a
command transcript, kernel patch hashes, and the paper draft artifacts available
at bundle time.
