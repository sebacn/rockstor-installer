#!/usr/bin/env bash
# Move Rockstor HC4 disk from FAT@2048 to FAT@8192 and install working AML U-Boot
# (large Armbian-style blob). Fixes ROM LOOP after openSUSE U-Boot at LBA0 and
# BL33/FAT overlap when FAT was at 2048.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UBOOT="${ROCKSTOR_HC4_WORKING_UBOOT:-${REPO_ROOT}/root/boot/u-boot-hc4-sda-working.bin}"
BOOT_SRC="${ROCKSTOR_HC4_BOOT_SRC:-/mnt/bdata/kiwi-images-hc4/build/image-root/boot}"
CACHE_DIR="${ROCKSTOR_HC4_MIGRATE_CACHE:-/mnt/bdata/hc4-migrate-cache}"
FIRST_PART_START=8192

_expand_hc4_root_partition() {
	local disk=$1 root_part=$2
	# Kiwi dracut first-boot repart hangs/timeouts when most of the SD is unallocated.
	umount "$root_part" 2>/dev/null || true
	if ! parted -s "$disk" resizepart 3 100% 2>/dev/null; then
		echo "WARNING: could not grow partition 3 on $disk (is it mounted?)" >&2
		return 0
	fi
	partprobe "$disk" 2>/dev/null || true
	sleep 1
	local mnt
	mnt=$(mktemp -d)
	if mount "$root_part" "$mnt" 2>/dev/null; then
		btrfs filesystem resize max "$mnt" || true
		if btrfs subvolume list "$mnt" | grep -q 'path @/.snapshots/1/snapshot'; then
			btrfs subvolume set-default "$mnt/@/.snapshots/1/snapshot" 2>/dev/null || true
		elif btrfs subvolume list "$mnt" | grep -q 'path @'; then
			btrfs subvolume set-default "$mnt/@" 2>/dev/null || true
		fi
		umount "$mnt"
	fi
	rmdir "$mnt" 2>/dev/null || true
	echo "Expanded btrfs root to fill $disk (skips kiwi OEM repart on first boot)."
}

usage() {
	echo "Usage: sudo $0 /dev/sdX" >&2
	exit 1
}

[[ $# -eq 1 ]] || usage
DEV="$1"
[[ -b "$DEV" ]] || { echo "Not a block device: $DEV" >&2; exit 1; }

case "$DEV" in
*/mmcblk*|/dev/sd*) ;;
*) echo "Refusing device: $DEV" >&2; exit 1 ;;
esac

if [[ "$(id -u)" -ne 0 ]]; then
	echo "Run as root (sudo $0 $DEV)" >&2
	exit 1
fi

[[ -f "$UBOOT" ]] || {
	echo "Missing working U-Boot: $UBOOT" >&2
	exit 1
}

case "$DEV" in
*/mmcblk*) P1="${DEV}p1" P2="${DEV}p2" P3="${DEV}p3" ;;
*) P1="${DEV}1" P2="${DEV}2" P3="${DEV}3" ;;
esac

for p in "$P1" "$P2" "$P3"; do umount "$p" 2>/dev/null || true; done
swapoff "$P2" 2>/dev/null || true
# Catch automount paths (e.g. /media/$USER/ROOT)
while read -r mnt; do
	[[ -n "$mnt" ]] && umount "$mnt" 2>/dev/null || true
done < <(lsblk -ln -o MOUNTPOINT "$DEV" | grep -v '^$' || true)

mapfile -t parts < <(fdisk -l "$DEV" 2>/dev/null | awk '/^\/dev\//{print $1,$2,$4,$5}')
# Expect p1 p2 p3 lines
get_start_sectors() {
	local p=$1
	fdisk -l "$DEV" 2>/dev/null | awk -v d="$p" '$1==d {print $2}'
}
get_size_sectors() {
	local p=$1
	fdisk -l "$DEV" 2>/dev/null | awk -v d="$p" '$1==d {print $4}'
}

OLD_P1_START=$(get_start_sectors "$P1")
P1_SECTORS=$(get_size_sectors "$P1")
P2_SECTORS=$(get_size_sectors "$P2")
P3_SECTORS=$(get_size_sectors "$P3")
OLD_P3_START=$(get_start_sectors "$P3")

if [[ -z "$P1_SECTORS" || -z "$P3_SECTORS" ]]; then
	echo "Could not read partition table on $DEV" >&2
	fdisk -l "$DEV" >&2 || true
	exit 1
fi

if [[ "$OLD_P1_START" == "$FIRST_PART_START" ]]; then
	echo "Partition 1 already starts at $FIRST_PART_START; refreshing U-Boot + FAT ..."
	dd if="$UBOOT" of="$DEV" conv=fsync,notrunc bs=1 count=442 status=none
	dd if="$UBOOT" of="$DEV" conv=fsync,notrunc bs=512 skip=1 seek=1 status=none
	ROCKSTOR_HC4_UBOOT_FOR_INSTALL="$UBOOT" ROCKSTOR_HC4_BOOT_PART_START="$FIRST_PART_START" \
		"${REPO_ROOT}/scripts/repair-hc4-boot-fat.sh" "$DEV"
	_expand_hc4_root_partition "$DEV" "$P3"
	exit 0
fi

mkdir -p "$CACHE_DIR"
ROOT_IMG="${CACHE_DIR}/$(basename "$DEV")-p3.img"
echo "Saving btrfs partition (${P3_SECTORS} sectors) to ${ROOT_IMG} ..."
dd if="$P3" of="$ROOT_IMG" bs=512 status=progress conv=fsync

echo "Writing AML U-Boot from ${UBOOT} ..."
dd if="$UBOOT" of="$DEV" conv=fsync,notrunc bs=1 count=442 status=none
dd if="$UBOOT" of="$DEV" conv=fsync,notrunc bs=512 skip=1 seek=1 status=none

NEW_P1_START=$FIRST_PART_START
NEW_P2_START=$((NEW_P1_START + P1_SECTORS))
NEW_P3_START=$((NEW_P2_START + P2_SECTORS))

echo "New layout: p1@${NEW_P1_START} p2@${NEW_P2_START} p3@${NEW_P3_START} (was p1@${OLD_P1_START} p3@${OLD_P3_START})"

# sfdisk: start, size, type, bootable
sfdisk --force "$DEV" <<EOF
label: dos
unit: sectors

start=${NEW_P1_START}, size=${P1_SECTORS}, type=c
start=${NEW_P2_START}, size=${P2_SECTORS}, type=82
start=${NEW_P3_START}, size=${P3_SECTORS}, type=83
EOF

partprobe "$DEV" 2>/dev/null || true
sleep 1

case "$DEV" in
*/mmcblk*) P1="${DEV}p1" P2="${DEV}p2" P3="${DEV}p3" ;;
*) P1="${DEV}1" P2="${DEV}2" P3="${DEV}3" ;;
esac

echo "Restoring btrfs to ${P3} ..."
dd if="$ROOT_IMG" of="$P3" bs=512 status=progress conv=fsync

mkswap -L SWAP "$P2" >/dev/null

mkfs.vfat -F 32 -n BOOT "$P1"
mnt=$(mktemp -d)
mount "$P1" "$mnt"
cp "${BOOT_SRC}/Image" "${BOOT_SRC}/initrd" "$mnt/"
"${REPO_ROOT}/scripts/patch-hc4-initrd.sh" "$mnt/initrd"
"${REPO_ROOT}/scripts/build-hc4-linux-dtb.sh" "${REPO_ROOT}/root/boot/odroid-hc4.dtb"
cp "${REPO_ROOT}/root/boot/odroid-hc4.dtb" "$mnt/"
mkdir -p "$mnt/extlinux"
cp "${REPO_ROOT}/root/boot/extlinux/extlinux.conf" "$mnt/extlinux/"
sync
umount "$mnt"
rmdir "$mnt"

_expand_hc4_root_partition "$DEV" "$P3"

echo "Migration complete. Safe to remove ${ROOT_IMG} after boot test."
echo "Boot HC4 from microSD; U-Boot should pass ROM + load extlinux from mmc 0:1."
