#!/usr/bin/env bash
# Extract u-boot.bin from a bootable ODROID-HC4 (or Armbian HC4) block device.
# Layout matches Armbian platform_install.sh (442 bytes @ LBA0 + payload @ sector 1).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${1:-${REPO_ROOT}/root/boot/u-boot-hc4-from-disk.bin}"
DEV="${2:-}"

if [[ -z "$DEV" ]]; then
	echo "Usage: $0 [output.bin] /dev/sdX" >&2
	exit 1
fi
if [[ -n "${1:-}" && -b "${1:-}" ]]; then
	DEV="$1"
	DEST="${REPO_ROOT}/root/boot/u-boot-hc4-from-disk.bin"
fi

[[ -b "$DEV" ]] || { echo "Not a block device: $DEV" >&2; exit 1; }

SIZE="${UBOOT_EXTRACT_SIZE:-1344368}"
for part in $(lsblk -ln -o NAME,TYPE "$DEV" | awk '$2=="part"{print "/dev/"$1}'); do
	umount "$part" 2>/dev/null || true
done

rm -f "$DEST"
dd if="$DEV" of="$DEST" bs=1 count=442 status=none
dd if="$DEV" of="$DEST" bs=1 skip=512 seek=512 conv=notrunc count=$((SIZE - 512)) status=none
echo "extract-uboot-odroid-hc4-from-disk: wrote ${DEST} (${SIZE} bytes) from ${DEV}"
echo "Install into image overlay: cp ${DEST} ${REPO_ROOT}/root/boot/u-boot.bin"
echo "Or write to card: scripts/write-uboot-odroid-hc4-to-disk.sh ${DEV}"
