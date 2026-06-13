# Reproducible build environment for the STM32N6 AI demos.
# Pins the Arm GNU bare-metal toolchain and GNU Make so builds do not depend on
# whatever happens to be installed on the host (Homebrew, system make, etc.).
#
# The host architecture is auto-detected, so this image builds natively on both
# Apple Silicon (aarch64 Linux container) and x86_64 hosts.
FROM ubuntu:24.04

ARG TC_VER=15.2.rel1
ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl xz-utils make git python3 \
    && rm -rf /var/lib/apt/lists/*

# Arm GNU Toolchain (matches the version verified on the host: 15.2.rel1).
RUN set -eux; \
    case "$(uname -m)" in \
        aarch64|arm64) host=aarch64 ;; \
        x86_64|amd64)  host=x86_64 ;; \
        *) echo "unsupported arch: $(uname -m)" >&2; exit 1 ;; \
    esac; \
    url="https://developer.arm.com/-/media/Files/downloads/gnu/${TC_VER}/binrel/arm-gnu-toolchain-${TC_VER}-${host}-arm-none-eabi.tar.xz"; \
    curl -fSL "$url" -o /tmp/tc.tar.xz; \
    mkdir -p /opt/arm-toolchain; \
    tar -xJf /tmp/tc.tar.xz -C /opt/arm-toolchain --strip-components=1; \
    rm /tmp/tc.tar.xz; \
    /opt/arm-toolchain/bin/arm-none-eabi-gcc --version | head -1

ENV PATH="/opt/arm-toolchain/bin:${PATH}"
WORKDIR /work
