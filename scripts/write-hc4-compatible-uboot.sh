#!/usr/bin/env bash
# Write HC4-compatible U-Boot only (does not touch FAT /boot). Use when FAT is OK but BL33 CHK loops after mkfs.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export UBOOT="${ROCKSTOR_HC4_UBOOT_FOR_INSTALL:-${REPO_ROOT}/root/boot/u-boot.bin}"
exec sudo -E "${REPO_ROOT}/scripts/write-uboot-odroid-hc4-to-disk.sh" "$@"
