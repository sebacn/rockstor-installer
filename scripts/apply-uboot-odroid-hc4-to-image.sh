#!/usr/bin/env bash
# Write Armbian U-Boot to a HC4 disk image file or whole block device (442 @0 + payload @sector 1).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UBOOT="${ROCKSTOR_HC4_UBOOT_BIN:-${REPO_ROOT}/root/boot/u-boot.bin}"

usage() {
	echo "Usage: $0 <path/to/image.raw|/dev/sdX>" >&2
	exit 2
}

[[ $# -eq 1 ]] || usage
TARGET="$1"
[[ -f "$TARGET" || -b "$TARGET" ]] || { echo "Not a file or block device: $TARGET" >&2; exit 1; }
[[ -f "$UBOOT" ]] || { echo "Missing $UBOOT (run scripts/fetch-uboot-odroid-hc4.sh)" >&2; exit 1; }

if [[ -b "$TARGET" ]]; then
	for part in $(lsblk -ln -o NAME,TYPE "$TARGET" | awk '$2=="part"{print "/dev/"$1}'); do
		umount "$part" 2>/dev/null || true
	done
fi

echo "apply-uboot-odroid-hc4: writing ${UBOOT} -> ${TARGET}"
dd if="$UBOOT" of="$TARGET" conv=fsync,notrunc bs=1 count=442
dd if="$UBOOT" of="$TARGET" conv=fsync,notrunc bs=512 skip=1 seek=1
sync
"${REPO_ROOT}/scripts/validate-hc4-raw-uboot.sh" "$TARGET" "$UBOOT"
