#!/usr/bin/env bash
# Tumbleweed.OdroidHC4 kiwi-ng build in rockstor-worker:arm64 (MBR + U-Boot).
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IMAGE="${ROCKSTOR_WORKER_IMAGE:-rockstor-worker:arm64}"
CONTAINER_NAME="${ROCKSTOR_KIWI_CONTAINER:-rockstor-odroid-hc4-build}"
if [[ -z "${ROCKSTOR_KIWI_TARGET:-}" && ! -d /mnt/bdata ]]; then
  TARGET_DIR="${HOME}/kiwi-images-hc4"
  CACHE_DIR="${HOME}/kiwi-cache"
  KIWI_VAR_TMP="${HOME}/kiwi-var-tmp"
else
  TARGET_DIR="${ROCKSTOR_KIWI_TARGET:-/mnt/bdata/kiwi-images-hc4}"
  CACHE_DIR="${ROCKSTOR_KIWI_CACHE:-/mnt/bdata/cache}"
  KIWI_VAR_TMP="${ROCKSTOR_KIWI_VAR_TMP:-/mnt/bdata/kiwi-var-tmp}"
fi
LOG="${ROCKSTOR_KIWI_LOG:-$HOME/kiwi-build-odroid-hc4.log}"
PROFILE="${ROCKSTOR_KIWI_PROFILE:-Tumbleweed.OdroidHC4}"
KIWI_PREP_PKGS="util-linux util-linux-systemd pam_pwquality device-mapper kpartx parted systemd"
run_root() { if [[ "$(id -u)" -eq 0 ]]; then "$@"; else sudo "$@"; fi; }
if [[ "${DOCKER_HOST:-}" == *"/run/user/"*"/docker.sock" ]]; then
  echo "WARNING: rootless Docker (DOCKER_HOST=${DOCKER_HOST}) cannot run kiwi-ng system build." >&2
  echo "Use system Docker instead: sudo -E bash scripts/run-hc4-system-docker-build.sh" >&2
fi
export ROCKSTOR_KIWI_TARGET="$TARGET_DIR" ROCKSTOR_KIWI_CACHE="$CACHE_DIR" ROCKSTOR_KIWI_VAR_TMP="$KIWI_VAR_TMP"
export ROCKSTOR_WORKER_IMAGE="$IMAGE"
export ROCKSTOR_UBOOT_SOURCE="${ROCKSTOR_UBOOT_SOURCE:-armbian}"
bash "$REPO_ROOT/scripts/prepare-hc4-build-host.sh" --docker
bash "$REPO_ROOT/scripts/validate-hc4-build-host.sh" --docker
run_root modprobe loop max_part=8 2>/dev/null || true
run_root sysctl -w fs.protected_symlinks=0 fs.protected_hardlinks=0 2>/dev/null || true
run_root mkdir -p "$TARGET_DIR" "$CACHE_DIR" "$TARGET_DIR/tmp" "$KIWI_VAR_TMP"
if [[ "${ROCKSTOR_KIWI_CLEAR_CACHE:-0}" == 1 ]]; then
  echo "ROCKSTOR_KIWI_CLEAR_CACHE=1: removing $CACHE_DIR" | run_root tee -a "$LOG" >/dev/null
  run_root rm -rf "$CACHE_DIR"
  run_root mkdir -p "$CACHE_DIR"
elif [[ "${ROCKSTOR_KIWI_REFRESH_REPOS:-0}" == 1 ]]; then
  echo "ROCKSTOR_KIWI_REFRESH_REPOS=1: refreshing zypper metadata in $CACHE_DIR" | run_root tee -a "$LOG" >/dev/null
  run_root rm -rf "$CACHE_DIR/zypper/solv" "$CACHE_DIR/zypper/repos" "$CACHE_DIR/zypper/raw"
fi
run_root touch "$LOG"
run_root chmod 666 "$LOG" 2>/dev/null || run_root chown "$(id -un):$(id -gn)" "$LOG"
run_root docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
sleep 2
run_root rm -rf "$TARGET_DIR/build" "$TARGET_DIR"/*.raw "$TARGET_DIR"/*.changes "$TARGET_DIR"/*.packages "$TARGET_DIR"/*.verified "$TARGET_DIR"/kiwi.result "$TARGET_DIR"/kiwi.result.json 2>/dev/null || true
run_root mkdir -p "$TARGET_DIR"
# u-boot.bin fetched by prepare-hc4-build-host.sh (unless ROCKSTOR_SKIP_UBOOT_FETCH=1)
if [[ ! -f "$REPO_ROOT/root/boot/u-boot.bin" ]]; then
  echo "Missing $REPO_ROOT/root/boot/u-boot.bin (run scripts/fetch-uboot-odroid-hc4.sh on the host; needs dpkg-deb for Armbian .deb)" >&2
  exit 1
fi
echo "=== BUILD $(date -Iseconds) profile=$PROFILE target=$TARGET_DIR ===" | run_root tee -a "$LOG" >/dev/null
run_root docker run -d --name "$CONTAINER_NAME" --privileged --cap-add SYS_ADMIN \
  --security-opt seccomp=unconfined \
  --pid=host \
  -v /dev:/dev \
  -v "$REPO_ROOT:/workspace" \
  -v "$TARGET_DIR:/home/kiwi-images" \
  -v "$CACHE_DIR:/kiwi-package-cache" \
  -v "$KIWI_VAR_TMP:/var/tmp" \
  -e TMPDIR=/var/tmp \
  -w /workspace \
  "$IMAGE" \
  sudo bash -c 'set -e; zypper --non-interactive in -y '"$KIWI_PREP_PKGS"'; command -v lsblk >/dev/null; modprobe loop max_part=8 2>/dev/null || true; sysctl -w fs.protected_symlinks=0 fs.protected_hardlinks=0 >/dev/null 2>&1 || true; bash /workspace/scripts/patch-kiwi-msdos-mbsize.sh; exec kiwi-ng --shared-cache-dir=/kiwi-package-cache --profile='"$PROFILE"' --type oem system build --description ./ --target-dir /home/kiwi-images/' \
  >/dev/null
echo "Started $CONTAINER_NAME profile=$PROFILE (detached). Log: docker logs -f $CONTAINER_NAME  (or tee $LOG)"
