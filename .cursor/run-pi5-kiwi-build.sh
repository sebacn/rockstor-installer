#!/usr/bin/env bash
# Pi5 kiwi-ng build in rockstor-worker:arm64 with host /dev for loop partitions.
#
# Requires: docker, sudo, arm64 host, image rockstor-worker:arm64 (see worker.Dockerfile).
# Override output location when root filesystem is tight (15 GB+ free required), e.g.:
#   export ROCKSTOR_KIWI_TARGET=/mnt/bdata/kiwi-images
#   export ROCKSTOR_KIWI_LOG=/mnt/bdata/kiwi-build.log
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IMAGE="${ROCKSTOR_WORKER_IMAGE:-rockstor-worker:arm64}"
CONTAINER_NAME="${ROCKSTOR_KIWI_CONTAINER:-rockstor-pi5-build}"
TARGET_DIR="${ROCKSTOR_KIWI_TARGET:-$HOME/kiwi-images}"
CACHE_DIR="${ROCKSTOR_KIWI_CACHE:-$TARGET_DIR/.kiwi-package-cache}"
LOG="${ROCKSTOR_KIWI_LOG:-$HOME/kiwi-build.log}"
run_root() { if [[ "$(id -u)" -eq 0 ]]; then "$@"; else sudo "$@"; fi; }
run_root modprobe loop max_part=8 2>/dev/null || true
run_root mkdir -p "$TARGET_DIR" "$CACHE_DIR"
if [[ "${ROCKSTOR_KIWI_CLEAR_CACHE:-0}" == 1 ]]; then
  echo "ROCKSTOR_KIWI_CLEAR_CACHE=1: removing $CACHE_DIR" | run_root tee -a "$LOG" >/dev/null
  run_root rm -rf "$CACHE_DIR"
  run_root mkdir -p "$CACHE_DIR"
fi
run_root touch "$LOG"
run_root chmod 666 "$LOG" 2>/dev/null || run_root chown "$(id -un):$(id -gn)" "$LOG"
run_root docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
run_root rm -rf "$TARGET_DIR/build"
echo "=== BUILD $(date -Iseconds) loop-partition docker target=$TARGET_DIR ===" | run_root tee -a "$LOG" >/dev/null
nohup run_root bash -c "docker run --name '$CONTAINER_NAME' --privileged --cap-add SYS_ADMIN \
  -v /dev:/dev \
  -v '$REPO_ROOT:/workspace' \
  -v '$TARGET_DIR:/home/kiwi-images' \
  -v '$CACHE_DIR:/kiwi-package-cache' \
  -w /workspace \
  '$IMAGE' \
  sudo bash -c 'zypper --non-interactive in -y device-mapper kpartx parted systemd >/dev/null 2>&1 || true; modprobe loop max_part=8 2>/dev/null || true; exec kiwi-ng --profile=Tumbleweed.RaspberryPi5 --type oem system build --description ./ --target-dir /home/kiwi-images/ --shared-cache-dir=/kiwi-package-cache' \
  >>'$LOG' 2>&1" >/dev/null 2>&1 &
echo "Started $CONTAINER_NAME (PID $!). Log: $LOG"
