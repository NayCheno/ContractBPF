FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    bc \
    bison \
    build-essential \
    ca-certificates \
    cpio \
    curl \
    dwarves \
    flex \
    gzip \
    libelf-dev \
    libssl-dev \
    make \
    musl-tools \
    qemu-system-x86 \
    xz-utils \
    && rm -rf /var/lib/apt/lists/*
