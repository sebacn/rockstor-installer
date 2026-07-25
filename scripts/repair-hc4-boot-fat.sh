#!/usr/bin/env bash
# Recreate HC4 FAT /boot (Image, initrd, extlinux) after U-Boot overwrote LBA 2048+.
# Does not rewrite U-Boot or root btrfs. Run on the Pi with the SD/USB disk attached.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BOOT_SRC="${REPO_ROOT}/root/boot"
FALLBACK_SRC="${ROCKSTOR_HC4_BOOT_SRC:-/mnt/bdata/kiwi-images-hc4/build/image-root/boot}"

usage() {
	echo "Usage: sudo $0 /dev/sdX" >&2
	echo "  Expects ${1:-/dev/sdX}1 = FAT boot, ${1:-/dev/sdX}3 = btrfs ROOT (Rockstor HC4 layout)." >&2
	exit 1
}

[[ $# -eq 1 ]] || usage
DEV="$1"
[[ -b "$DEV" ]] || { echo "Not a block device: $DEV" >&2; exit 1; }

case "$DEV" in
*/mmcblk*|/dev/loop*) BOOT_PART="${DEV}p1" ;;
*) BOOT_PART="${DEV}1" ;;
esac

[[ -b "$BOOT_PART" ]] || { echo "Missing boot partition: $BOOT_PART" >&2; exit 1; }

src_dir="$BOOT_SRC"
if [[ ! -f "${src_dir}/Image" && -f "${FALLBACK_SRC}/Image" ]]; then
	src_dir="$FALLBACK_SRC"
fi
[[ -f "${src_dir}/Image" && -f "${src_dir}/initrd" ]] || {
	echo "Need Image and initrd under ${src_dir} (or set ROCKSTOR_HC4_BOOT_SRC)" >&2
	exit 1
}

for part in $(lsblk -ln -o NAME,TYPE "$DEV" | awk '$2=="part"{print "/dev/"$1}'); do
	umount "$part" 2>/dev/null || true
done
swapoff -a 2>/dev/null || :

echo "Formatting ${BOOT_PART} (FAT32 BOOT) ..."
mkfs.vfat -F 32 -n BOOT "${BOOT_PART}"

mnt=$(mktemp -d)
mount "${BOOT_PART}" "$mnt"
cp "${src_dir}/Image" "${src_dir}/initrd" "$mnt/"
extlinux_src="${REPO_ROOT}/root/boot/extlinux/extlinux.conf"
if [[ -f "${extlinux_src}" ]]; then
	mkdir -p "$mnt/extlinux"
	cp "${extlinux_src}" "$mnt/extlinux/"
elif [[ -f "${src_dir}/extlinux/extlinux.conf" ]]; then
	mkdir -p "$mnt/extlinux"
	cp "${src_dir}/extlinux/extlinux.conf" "$mnt/extlinux/"
fi
sync
umount "$mnt"
rmdir "$mnt"
echo "Done. On HC4: reset or 'reset' at U-Boot; should load extlinux from mmc 0:1."
echo "Verify on PC: mount ${BOOT_PART} and ls; or in U-Boot: fatls mmc 0:1"
