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
boot_start="${ROCKSTOR_HC4_BOOT_PART_START:-8192}"
if (( last_sector >= boot_start )); then
	echo "ERROR: ${UBOOT} ends at sector ${last_sector}; boot partition starts at ${boot_start}." >&2
	echo "       Use migrate-hc4-disk-armbian-layout.sh or kiwi disk_start_sector=8192." >&2
	exit 1
fi
if (( last_sector > 1919 )); then
	echo "WARNING: u-boot.bin spans through sector ${last_sector}; HC4 wiki reserves 1–1919 for bootloader." >&2
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
