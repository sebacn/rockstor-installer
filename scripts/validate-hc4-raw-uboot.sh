#!/usr/bin/env bash
# Verify Armbian U-Boot is present at LBA0 + sector 1 on a HC4 .raw (or block device).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${1:-}"
UBOOT="${2:-${ROCKSTOR_HC4_UBOOT_BIN:-${REPO_ROOT}/root/boot/u-boot.bin}}"

usage() {
	echo "Usage: $0 <disk-image.raw|/dev/sdX> [u-boot.bin]" >&2
	exit 2
}

[[ -n "$IMAGE" ]] || usage
if [[ ! -f "$IMAGE" && ! -b "$IMAGE" ]]; then
	echo "validate-hc4-raw-uboot: not a file or block device: $IMAGE" >&2
	exit 1
fi
if [[ ! -f "$UBOOT" ]]; then
	echo "validate-hc4-raw-uboot: missing reference U-Boot: $UBOOT" >&2
	exit 1
fi

if ! dd if="$IMAGE" bs=1 count=442 2>/dev/null | cmp -s - "$UBOOT" -n 442; then
	echo "validate-hc4-raw-uboot: ERROR: bytes 0–441 do not match ${UBOOT} on ${IMAGE}" >&2
	exit 1
fi

# Sector 1 should match u-boot.bin payload (skip 442-byte header, dd sector-aligned part).
if ! dd if="$IMAGE" bs=512 skip=1 count=1 2>/dev/null | cmp -s - <(dd if="$UBOOT" bs=512 skip=1 count=1 2>/dev/null); then
	echo "validate-hc4-raw-uboot: ERROR: sector 1 payload mismatch on ${IMAGE}" >&2
	exit 1
fi

echo "validate-hc4-raw-uboot: OK: Armbian U-Boot layout present on ${IMAGE}"
