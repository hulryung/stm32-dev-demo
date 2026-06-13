#!/usr/bin/env bash
#
# Build an STM32N6 demo inside a container so the toolchain is reproducible.
#
# Runtime selection:
#   - Apple Silicon with Apple's `container` CLI  -> uses `container`
#   - otherwise, if Docker is installed           -> uses `docker`
#
# Usage:
#   scripts/build.sh [make-args...]
#
# Env overrides:
#   DEMO=<dir>     demo directory to build   (default: x-cube-n6-ai-people-detection-tracking)
#   IMAGE=<name>   builder image tag         (default: stm32n6-builder)
#   RUNTIME=...    force "container" or "docker"
#   MEM=<size>     container memory          (default: 8g; raise if you hit OOM "Killed")
#   JOBS=<n>       parallel compile jobs      (default: 6)
#
# Examples:
#   scripts/build.sh              # full build
#   scripts/build.sh clean        # clean
#   scripts/build.sh -j4          # limit parallelism
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${IMAGE:-stm32n6-builder}"
DEMO="${DEMO:-x-cube-n6-ai-people-detection-tracking}"
DEMO_DIR="$ROOT/$DEMO"
MEM="${MEM:-8g}"
JOBS="${JOBS:-6}"

if [ ! -f "$DEMO_DIR/Makefile" ]; then
    echo "error: $DEMO_DIR/Makefile not found." >&2
    echo "       run: git submodule update --init --recursive" >&2
    exit 1
fi

# --- pick a container runtime -------------------------------------------------
RT="${RUNTIME:-}"
if [ -z "$RT" ]; then
    if [ "$(uname -m)" = "arm64" ] && command -v container >/dev/null 2>&1; then
        RT=container
    elif command -v docker >/dev/null 2>&1; then
        RT=docker
    else
        echo "error: no container runtime found." >&2
        echo "       install Apple 'container' (Apple Silicon) or Docker." >&2
        exit 1
    fi
fi
echo ">> runtime: $RT"

# Apple's container service must be running before build/run.
if [ "$RT" = "container" ]; then
    if ! container system status >/dev/null 2>&1; then
        echo ">> starting Apple container services..."
        container system start
    fi
fi

# --- build the image ----------------------------------------------------------
echo ">> building image '$IMAGE' (first run downloads the toolchain ~150MB)..."
"$RT" build -t "$IMAGE" -f "$ROOT/docker/Dockerfile" "$ROOT/docker"

# --- compile ------------------------------------------------------------------
echo ">> compiling '$DEMO' (mem=$MEM, jobs=$JOBS)..."
"$RT" run --rm \
    -m "$MEM" \
    -v "$DEMO_DIR:/work" \
    -w /work \
    "$IMAGE" \
    bash -c '
        set -e
        # ST ships -fcyclomatic-complexity in the Makefile; it is an IAR/legacy
        # flag that mainline GCC rejects. Strip it (idempotent, safe to re-run).
        sed -i "s/ -fcyclomatic-complexity//g" Makefile
        make "$@"
    ' _ "-j${JOBS}" "$@"

echo ">> done. Artifacts: $DEMO/build/Project.{elf,hex,bin}"
