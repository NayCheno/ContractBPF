# syntax=docker/dockerfile:1
FROM ubuntu:24.04

LABEL org.opencontainers.image.title="ContractBPF Ubuntu workspace"
LABEL org.opencontainers.image.description="Ubuntu toolchain image for ContractBPF kernel, QEMU, Rust userspace, BPF, workloads, and experiments"

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Etc/UTC
ENV RUSTUP_HOME=/opt/rustup
ENV PATH=/opt/cargo/bin:${PATH}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    bc \
    bison \
    build-essential \
    ca-certificates \
    cargo \
    clang \
    cmake \
    coreutils \
    cpio \
    curl \
    diffutils \
    dwarves \
    expect \
    file \
    findutils \
    flex \
    gawk \
    git \
    grep \
    gzip \
    kmod \
    libbpf-dev \
    libcap-dev \
    libelf-dev \
    libssl-dev \
    libunwind-dev \
    libzstd-dev \
    lld \
    llvm \
    make \
    memcached \
    musl-tools \
    ninja-build \
    openssh-client \
    openssl \
    patch \
    pkg-config \
    procps \
    psmisc \
    python3 \
    python3-pip \
    python3-venv \
    qemu-system-x86 \
    qemu-utils \
    rsync \
    sed \
    tar \
    unzip \
    util-linux \
    wget \
    xz-utils \
    zlib1g-dev \
    zstd \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://sh.rustup.rs \
    | CARGO_HOME=/opt/cargo RUSTUP_HOME=/opt/rustup RUSTUP_INIT_SKIP_PATH_CHECK=yes \
      sh -s -- -y --profile minimal --default-toolchain stable \
    && /opt/cargo/bin/rustc --version \
    && /opt/cargo/bin/cargo --version \
    && /opt/cargo/bin/rustup component add rustfmt

WORKDIR /workspace

CMD ["/bin/bash"]
