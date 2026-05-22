FROM debian:stable-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential cpio gzip qemu-system-x86 ca-certificates curl xz-utils \
    bc flex bison dwarves libssl-dev libelf-dev make \
    && rm -rf /var/lib/apt/lists/*

