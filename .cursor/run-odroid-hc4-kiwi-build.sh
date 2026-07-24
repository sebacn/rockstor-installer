#!/usr/bin/env bash
# Tumbleweed.OdroidHC4 kiwi-ng build in rockstor-worker:arm64 (MBR + U-Boot).
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IMAGE="${ROCKSTOR_WORKER_IMAGE:-rockstor-worker:arm64}"
CONTAINER_NAME="${ROCKSTOR_KIWI_CONTAINER:-rockstor-odroid-hc4-build}"
TARGET_DIR="${ROCKSTOR_KIWI_TARGET:-$HOME/kiwi-images}"
LOG="${ROCKSTOR_KIWI_LOG:-$HOME/kiwi-build-odroid-hc4.log}"
PROFILE="${ROCKSTOR_KIWI_PROFILE:-Tumbleweed.OdroidHC4}"
run_root() { if [[ "$(id -u)" -eq 0 ]]; then "$@"; else sudo "$@"; fi; }
run_root modprobe loop max_part=8 2>/dev/null || true
run_root mkdir -p "$TARGET_DIR"
run_root touch "$LOG"
run_root chmod 666 "$LOG" 2>/dev/null || run_root chown "$(id -un):$(id -gn)" "$LOG"
run_root docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
run_root rm -rf "$TARGET_DIR/build"
echo "=== BUILD $(date -Iseconds) profile=$PROFILE target=$TARGET_DIR ===" | run_root tee -a "$LOG" >/dev/null
nohup run_root bash -c "docker run --name '$CONTAINER_NAME' --privileged --cap-add SYS_ADMIN \
  -v /dev:/dev \
  -v '$REPO_ROOT:/workspace' \
  -v '$TARGET_DIR:/home/kiwi-images' \
  -w /workspace \
  '$IMAGE' \
  sudo bash -c 'zypper --non-interactive in -y device-mapper kpartx parted systemd >/dev/null 2>&1 || true; modprobe loop max_part=8 2>/dev/null || true; exec kiwi-ng --profile=$PROFILE --type oem system build --description ./ --target-dir /home/kiwi-images/' \
  >>'$LOG' 2>&1" >/dev/null 2>&1 &
echo "Started $CONTAINER_NAME profile=$PROFILE (PID $!). Log: $LOG"
