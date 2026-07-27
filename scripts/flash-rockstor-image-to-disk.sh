#!/usr/bin/env bash
# Interactive flash of Rockstor / HC4 installer images (.raw or .raw.xz) to a removable disk.
set -euo pipefail

DEFAULT_IMAGE_DIR="${ROCKSTOR_IMAGE_DIR:-${ROCKSTOR_KIWI_TARGET:-$HOME/kiwi-images-hc4}}"
ASSUME_YES=0
IMAGE_DIR=""
IMAGE_FILE=""
TARGET_DEV=""

usage() {
	cat <<EOF
Usage: $0 [options]

Flash a kiwi disk image to an SD card / USB adapter (dd). Supports uncompressed
.raw/.img and .xz-compressed images (decompressed on the fly).

Options:
  --image-dir PATH   Directory to list images (default: ${DEFAULT_IMAGE_DIR})
  --image PATH       Image file (skip image menu)
  --device DEV       Target block device e.g. /dev/sdb (skip device menu)
  -y, --yes          Do not ask for final confirmation

Environment:
  ROCKSTOR_IMAGE_DIR, ROCKSTOR_KIWI_TARGET  Default image search directory

Must be run as root (script re-execs via sudo when needed).
EOF
}

while [[ $# -gt 0 ]]; do
	case "$1" in
		--image-dir) IMAGE_DIR=$2; shift 2 ;;
		--image) IMAGE_FILE=$2; shift 2 ;;
		--device) TARGET_DEV=$2; shift 2 ;;
		-y|--yes) ASSUME_YES=1; shift ;;
		-h|--help) usage; exit 0 ;;
		*) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
	esac
done

if [[ "$(id -u)" -ne 0 ]]; then
	exec sudo -E "$0" "$@"
fi

if ! command -v dd >/dev/null 2>&1 || ! command -v lsblk >/dev/null 2>&1; then
	echo "ERROR: need dd and lsblk on PATH." >&2
	exit 1
fi

valid_block_dev() {
	local d=$1
	[[ -b "$d" ]] || return 1
	case "$d" in
		/dev/sd[a-z]|/dev/mmcblk[0-9]|/dev/nvme[0-9]n[0-9]) return 0 ;;
		*) return 1 ;;
	esac
}

disk_for_mount_source() {
	local src=$1
	local pk name
	[[ -n "$src" && -e "$src" ]] || return 1
	if [[ -b "$src" ]]; then
		pk=$(lsblk -no PKNAME "$src" 2>/dev/null | head -1)
		if [[ -n "$pk" ]]; then
			echo "/dev/${pk}"
			return 0
		fi
		echo "$src"
		return 0
	fi
	return 1
}

root_disk_device() {
	local src disk
	src=$(findmnt -n -o SOURCE / 2>/dev/null || true)
	disk=$(disk_for_mount_source "$src" || true)
	[[ -n "$disk" ]] && echo "$disk"
}

is_excluded_disk() {
	local dev=$1
	local root=$2
	if [[ -n "$root" && "$dev" == "$root" ]]; then
		return 0
	fi
	local mnt
	while read -r _mnt; do
		[[ "$_mnt" == "/" ]] && return 0
	done < <(lsblk -ln -o MOUNTPOINT "$dev" 2>/dev/null | grep -v '^$' || true)
	return 1
}

list_images() {
	local dir=$1
	[[ -d "$dir" ]] || return 1
	find "$dir" -maxdepth 1 -type f \( \
		-name '*.raw' -o -name '*.img' -o \
		-name '*.raw.xz' -o -name '*.img.xz' -o \
		-name '*.raw.txz' -o -name '*.txz' \
	\) ! -name '*.verified' 2>/dev/null | sort
}

human_size() {
	local bytes=$1
	if command -v numfmt >/dev/null 2>&1; then
		numfmt --to=iec-i --suffix=B "$bytes" 2>/dev/null || echo "${bytes} bytes"
	else
		echo "${bytes} bytes"
	fi
}

pick_image() {
	local dir=${1:-}
	local -a files=()
	local f i choice
	mapfile -t files < <(list_images "$dir" || true)
	if [[ ${#files[@]} -eq 0 ]]; then
		echo "No .raw / .img / .xz images found in: $dir" >&2
		return 1
	fi
	echo "Images in ${dir}:"
	for i in "${!files[@]}"; do
		printf '  %2d) %s (%s)\n' "$((i + 1))" "$(basename "${files[$i]}")" "$(human_size "$(stat -c%s "${files[$i]}")")"
	done
	echo "  q) Quit"
	while true; do
		read -r -p "Select image [1-${#files[@]}]: " choice
		case "$choice" in
			q|Q) return 1 ;;
			''|*[!0-9]*)
				echo "Enter a number or q." ;;
			*)
				if (( choice >= 1 && choice <= ${#files[@]} )); then
					echo "${files[$((choice - 1))]}"
					return 0
				fi
				echo "Out of range." ;;
		esac
	done
}

pick_disk() {
	local root_disk=$1
	local -a devs=() labels=()
	local line name size model tran pk
	while read -r name size model tran; do
		[[ -n "$name" ]] || continue
		pk="/dev/${name}"
		valid_block_dev "$pk" || continue
		if is_excluded_disk "$pk" "$root_disk"; then
			continue
		fi
		devs+=("$pk")
		labels+=("${pk}  ${size}  ${model:-unknown}  ${tran:-}")
	done < <(lsblk -d -n -o NAME,SIZE,MODEL,TRAN 2>/dev/null)
	if [[ ${#devs[@]} -eq 0 ]]; then
		echo "No suitable block devices (root disk ${root_disk:-?} is excluded)." >&2
		return 1
	fi
	echo "Target disks (root system disk excluded):"
	local i
	for i in "${!devs[@]}"; do
		printf '  %2d) %s\n' "$((i + 1))" "${labels[$i]}"
	done
	echo "  q) Quit"
	local choice
	while true; do
		read -r -p "Select destination [1-${#devs[@]}]: " choice
		case "$choice" in
			q|Q) return 1 ;;
			''|*[!0-9]*)
				echo "Enter a number or q." ;;
			*)
				if (( choice >= 1 && choice <= ${#devs[@]} )); then
					echo "${devs[$((choice - 1))]}"
					return 0
				fi
				echo "Out of range." ;;
		esac
	done
}

unmount_disk_partitions() {
	local dev=$1
	local part
	for part in $(lsblk -ln -o NAME,TYPE "$dev" | awk '$2=="part"{print "/dev/"$1}'); do
		umount "$part" 2>/dev/null || true
	done
}

flash_image() {
	local image=$1
	local dev=$2
	local use_xz=0
	case "$image" in
		*.xz|*.txz) use_xz=1 ;;
	esac
	if (( use_xz )); then
		if ! command -v xz >/dev/null 2>&1; then
			echo "ERROR: xz not found (install xz-utils)." >&2
			exit 1
		fi
	fi

	unmount_disk_partitions "$dev"
	sync

	echo "Flashing $(basename "$image") -> ${dev}"
	echo "Progress below (GNU dd status=progress; may pause during fsync at end)."

	if (( use_xz )); then
		if command -v pv >/dev/null 2>&1; then
			local uncomp
			uncomp=$(xz -l "$image" 2>/dev/null | awk '/Uncompressed size:/{print $5; exit}')
			if [[ -n "$uncomp" && "$uncomp" != "0" ]]; then
				pv -pte -s "$uncomp" "$image" | xz -dc | dd of="$dev" bs=4M conv=fsync status=progress
			else
				pv -pte "$image" | xz -dc | dd of="$dev" bs=4M conv=fsync status=progress
			fi
		else
			xz -dc "$image" | dd of="$dev" bs=4M conv=fsync status=progress
		fi
	else
		dd if="$image" of="$dev" bs=4M conv=fsync status=progress
	fi
	sync
	if command -v blockdev >/dev/null 2>&1; then
		blockdev --flushbufs "$dev" 2>/dev/null || true
	fi
	echo "Done. Safely remove the card or reboot from it."
}

# --- main ---

[[ -z "$IMAGE_DIR" ]] && IMAGE_DIR="$DEFAULT_IMAGE_DIR"

if [[ -z "$IMAGE_FILE" ]]; then
	if [[ ! -d "$IMAGE_DIR" ]]; then
		read -r -p "Image directory [$IMAGE_DIR]: " _dir
		IMAGE_DIR=${_dir:-$IMAGE_DIR}
	fi
	IMAGE_FILE=$(pick_image "$IMAGE_DIR") || exit 1
fi

[[ -f "$IMAGE_FILE" ]] || { echo "Not a file: $IMAGE_FILE" >&2; exit 1; }

ROOT_DISK=$(root_disk_device || true)
if [[ -z "$TARGET_DEV" ]]; then
	TARGET_DEV=$(pick_disk "$ROOT_DISK") || exit 1
fi

valid_block_dev "$TARGET_DEV" || { echo "Refusing device: $TARGET_DEV" >&2; exit 1; }
if [[ -n "$ROOT_DISK" ]] && [[ "$TARGET_DEV" == "$ROOT_DISK" ]]; then
	echo "ERROR: refusing to overwrite root disk $ROOT_DISK" >&2
	exit 1
fi

echo ""
echo "  Image:  $IMAGE_FILE"
echo "  Target: $TARGET_DEV"
lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINT "$TARGET_DEV" || true
echo ""
if [[ "$ASSUME_YES" != 1 ]]; then
	read -r -p "Type YES to erase ${TARGET_DEV}: " confirm
	[[ "$confirm" == YES ]] || { echo "Aborted."; exit 1; }
fi

flash_image "$IMAGE_FILE" "$TARGET_DEV"
