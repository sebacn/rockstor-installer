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

boot_start="${ROCKSTOR_HC4_BOOT_PART_START:-}"
if [[ -z "$boot_start" ]]; then
	boot_start=$(fdisk -l "$DEV" 2>/dev/null | awk -v p="${BOOT_PART##*/}" '$1 ~ p"$" {print $2; exit}')
	boot_start=${boot_start:-2048}
fi

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
"${REPO_ROOT}/scripts/patch-hc4-initrd.sh" "$mnt/initrd"
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

# Re-install U-Boot that fits below LBA 2048 (mkfs.vfat on p1 overwrites sectors 2048+).
uboot_install="${ROCKSTOR_HC4_UBOOT_FOR_INSTALL:-${REPO_ROOT}/root/boot/u-boot.bin}"
if [[ "${ROCKSTOR_HC4_SKIP_UBOOT_WRITE:-0}" != 1 && -f "${uboot_install}" ]]; then
	uboot_bytes=$(stat -c%s "${uboot_install}")
	last_sector=$((1 + (uboot_bytes - 442 + 511) / 512))
	if (( last_sector >= boot_start )); then
		echo "ERROR: ${uboot_install} overlaps boot FAT @ LBA ${boot_start} (ends sector ${last_sector})." >&2
		echo "       Run scripts/migrate-hc4-disk-armbian-layout.sh or use smaller U-Boot." >&2
		exit 1
	fi
	echo "Writing U-Boot from ${uboot_install} to ${DEV} (after FAT repair) ..."
	dd if="${uboot_install}" of="${DEV}" conv=fsync,notrunc bs=1 count=442 status=none
	dd if="${uboot_install}" of="${DEV}" conv=fsync,notrunc bs=512 skip=1 seek=1 status=none
	sync
else
	echo "Skipping U-Boot write (set ROCKSTOR_HC4_SKIP_UBOOT_WRITE=0 and install u-boot.bin to re-enable)."
fi

# mkfs.vfat gives /boot a new UUID; keep fstab on btrfs root in sync.
case "$DEV" in
*/mmcblk*) ROOT_PART="${DEV}p3" ;;
*) ROOT_PART="${DEV}3" ;;
esac
if [[ -b "$ROOT_PART" ]]; then
	boot_uuid=$(blkid -s UUID -o value "${BOOT_PART}" 2>/dev/null || true)
	if [[ -n "$boot_uuid" ]]; then
		root_mnt=$(mktemp -d)
		if mount -o rw "$ROOT_PART" "$root_mnt" 2>/dev/null; then
			if [[ -f "${root_mnt}/etc/fstab" ]]; then
				sed -i "s|^UUID=.* /boot vfat|UUID=${boot_uuid} /boot vfat|" "${root_mnt}/etc/fstab"
				echo "Updated /etc/fstab /boot UUID to ${boot_uuid}"
			fi
			umount "$root_mnt"
		fi
		rmdir "$root_mnt" 2>/dev/null || true
	fi
fi

echo "Done. On HC4: reset; fatls mmc 0:1 should list Image and extlinux."
