#!/usr/bin/env bash
# Write ODROID-HC4 U-Boot to a block device (same layout as Armbian platform_install.sh).
# Use after flashing a .raw image if the card loops with "BL33 CHK" on serial console.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UBOOT="${REPO_ROOT}/root/boot/u-boot.bin"

usage() {
	echo "Usage: $0 /dev/sdX" >&2
	echo "  Ensures ${UBOOT} exists (run scripts/fetch-uboot-odroid-hc4.sh first)." >&2
	exit 1
}

[[ $# -eq 1 ]] || usage
DEV="$1"
[[ -b "$DEV" ]] || { echo "Not a block device: $DEV" >&2; exit 1; }
case "$DEV" in
	/dev/sd[a-z]|/dev/mmcblk[0-9]|/dev/nvme*) ;;
	*) echo "Refusing unexpected device name: $DEV" >&2; exit 1 ;;
esac

if [[ ! -f "$UBOOT" ]]; then
	echo "Missing $UBOOT — run: ROCKSTOR_UBOOT_SOURCE=armbian scripts/fetch-uboot-odroid-hc4.sh" >&2
	exit 1
fi

# Hardkernel HC4: bootloader must fit in sectors 1–1919 (see wiki.odroid.com HC4 partition table).
uboot_bytes=$(stat -c%s "$UBOOT")
last_sector=$((1 + (uboot_bytes - 442 + 511) / 512))
if (( last_sector > 1919 )); then
	echo "WARNING: u-boot.bin spans through sector ${last_sector}; HC4 reserves 1–1919 for bootloader." >&2
	echo "         Image may still boot, but FAT at LBA 2048 can be overwritten by the U-Boot tail." >&2
fi

echo "Writing U-Boot from ${UBOOT} to ${DEV} (442 bytes @ LBA0 + payload @ sector 1) ..."
for part in $(lsblk -ln -o NAME,TYPE "$DEV" | awk '$2=="part"{print "/dev/"$1}'); do
	umount "$part" 2>/dev/null || true
done
swapoff -a 2>/dev/null || true

dd if="$UBOOT" of="$DEV" conv=fsync,notrunc bs=1 count=442
dd if="$UBOOT" of="$DEV" conv=fsync,notrunc bs=512 skip=1 seek=1
sync
echo "Done. Boot HC4 from microSD/eMMC (not SATA); hold recovery button if SPI flash still has old firmware."
