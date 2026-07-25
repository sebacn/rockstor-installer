#!/usr/bin/env bash
# Update FAT /boot on an HC4 SD (initrd patch + extlinux) without reformatting root.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BOOT_SRC="${ROCKSTOR_HC4_BOOT_SRC:-/mnt/bdata/kiwi-images-hc4/build/image-root/boot}"

usage() {
	echo "Usage: sudo $0 /dev/sdX" >&2
	exit 1
}

[[ $# -eq 1 ]] || usage
DEV="$1"
[[ -b "$DEV" ]] || { echo "Not a block device: $DEV" >&2; exit 1; }

case "$DEV" in
*/mmcblk*) P1="${DEV}p1" ;;
*) P1="${DEV}1" ;;
esac
[[ -b "$P1" ]] || { echo "Missing $P1" >&2; exit 1; }

src_dir="$REPO_ROOT/root/boot"
if [[ -f "${BOOT_SRC}/Image" && -f "${BOOT_SRC}/initrd" ]]; then
	src_dir="$BOOT_SRC"
fi
mnt=$(mktemp -d)
mount "$P1" "$mnt"
if [[ ! -f "${src_dir}/Image" || ! -f "${src_dir}/initrd" ]]; then
	if [[ -f "$mnt/Image" && -f "$mnt/initrd" ]]; then
		echo "Using Image+initrd already on ${P1}"
		src_dir="$mnt"
	else
		umount "$mnt"
		rmdir "$mnt"
		echo "Need Image+initrd in ${REPO_ROOT}/root/boot or on ${P1}" >&2
		exit 1
	fi
fi
if [[ "$src_dir" != "$mnt" ]]; then
	cp "${src_dir}/Image" "${src_dir}/initrd" "$mnt/"
fi
"${REPO_ROOT}/scripts/patch-hc4-initrd.sh" "$mnt/initrd"
"${REPO_ROOT}/scripts/build-hc4-linux-dtb.sh" "${REPO_ROOT}/root/boot/odroid-hc4.dtb"
cp "${REPO_ROOT}/root/boot/odroid-hc4.dtb" "$mnt/"
mkdir -p "$mnt/extlinux"
cp "${REPO_ROOT}/root/boot/extlinux/extlinux.conf" "$mnt/extlinux/"
sync
umount "$mnt"
rmdir "$mnt"
echo "Refreshed ${P1} (patched initrd + extlinux)."
