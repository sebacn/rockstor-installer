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

# kiwi edit_boot_install often runs with a minimal PATH (no cmp); use sha256 of byte ranges.
digest_range() {
	local file=$1 offset=$2 count=$3
	dd if="$file" bs=1 skip="$offset" count="$count" 2>/dev/null | sha256sum | awk '{print $1}'
}

digest_sector1() {
	local file=$1
	dd if="$file" bs=512 skip=1 count=1 2>/dev/null | sha256sum | awk '{print $1}'
}

h_img=$(digest_range "$IMAGE" 0 442)
h_uboot=$(digest_range "$UBOOT" 0 442)
if [[ -z "$h_img" || "$h_img" != "$h_uboot" ]]; then
	echo "validate-hc4-raw-uboot: ERROR: bytes 0–441 do not match ${UBOOT} on ${IMAGE}" >&2
	exit 1
fi

s_img=$(digest_sector1 "$IMAGE")
s_uboot=$(digest_sector1 "$UBOOT")
if [[ -z "$s_img" || "$s_img" != "$s_uboot" ]]; then
	echo "validate-hc4-raw-uboot: ERROR: sector 1 payload mismatch on ${IMAGE}" >&2
	exit 1
fi

echo "validate-hc4-raw-uboot: OK: Armbian U-Boot layout present on ${IMAGE}"
