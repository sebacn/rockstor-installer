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
  ROCKSTOR_FLASH_AUTO_INSTALL_DEPS=1        Install missing packages without prompting

Must be run as root (script re-execs via sudo when needed).
EOF
}

zypper_pkg_for_cmd() {
	case "$1" in
		dd|numfmt) echo coreutils ;;
		lsblk|findmnt|umount|blockdev) echo util-linux ;;
		xz) echo xz ;;
		pv) echo pv ;;
		*) return 1 ;;
	esac
}

apt_pkg_for_cmd() {
	case "$1" in
		dd|numfmt) echo coreutils ;;
		lsblk|findmnt|umount|blockdev) echo util-linux ;;
		xz) echo xz-utils ;;
		pv) echo pv ;;
		*) return 1 ;;
	esac
}

install_distro_packages() {
	local -a zypper_pkgs=() apt_pkgs=()
	local pkg
	for pkg in "$@"; do
		case "$pkg" in
			zypper:*) zypper_pkgs+=("${pkg#zypper:}") ;;
			apt:*) apt_pkgs+=("${pkg#apt:}") ;;
		esac
	done
	if [[ ${#zypper_pkgs[@]} -gt 0 ]] && command -v zypper >/dev/null 2>&1; then
		echo "Installing via zypper: ${zypper_pkgs[*]}"
		zypper --non-interactive install -y "${zypper_pkgs[@]}"
	elif [[ ${#apt_pkgs[@]} -gt 0 ]] && command -v apt-get >/dev/null 2>&1; then
		echo "Installing via apt: ${apt_pkgs[*]}"
		apt-get update -qq || true
		apt-get install -y "${apt_pkgs[@]}"
	else
		echo "ERROR: no supported package manager (zypper or apt-get) to install: $*" >&2
		return 1
	fi
}

# Offer to install distro packages for missing commands; exits 1 if still missing.
ensure_commands() {
	local -a cmds=("$@")
	local -a missing=()
	local cmd zypper_pkg apt_pkg
	local -a to_install=()
	local seen_zypper="" seen_apt=""
	local answer

	for cmd in "${cmds[@]}"; do
		command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
	done
	[[ ${#missing[@]} -eq 0 ]] && return 0

	echo "Missing command(s): ${missing[*]}"
	for cmd in "${missing[@]}"; do
		zypper_pkg=$(zypper_pkg_for_cmd "$cmd" || true)
		apt_pkg=$(apt_pkg_for_cmd "$cmd" || true)
		if [[ -z "$zypper_pkg" && -z "$apt_pkg" ]]; then
			echo "ERROR: no package mapping for '${cmd}'; install it manually." >&2
			exit 1
		fi
		[[ -n "$zypper_pkg" ]] && to_install+=("zypper:${zypper_pkg}")
		[[ -n "$apt_pkg" ]] && to_install+=("apt:${apt_pkg}")
		echo "  ${cmd} -> zypper: ${zypper_pkg:-n/a}, apt: ${apt_pkg:-n/a}"
	done

	# Deduplicate package entries.
	local -a unique_install=()
	local -A seen_zypper=() seen_apt=()
	local item p
	for item in "${to_install[@]}"; do
		case "$item" in
			zypper:*)
				p="${item#zypper:}"
				[[ -n "${seen_zypper[$p]:-}" ]] && continue
				seen_zypper[$p]=1
				unique_install+=("$item")
				;;
			apt:*)
				p="${item#apt:}"
				[[ -n "${seen_apt[$p]:-}" ]] && continue
				seen_apt[$p]=1
				unique_install+=("$item")
				;;
		esac
	done

	if [[ "${ROCKSTOR_FLASH_AUTO_INSTALL_DEPS:-0}" != 1 && "${ASSUME_YES}" != 1 ]]; then
		read -r -p "Install required package(s) now? [y/N] " answer
		[[ "$answer" == [yY] || "$answer" == [yY][eE][sS] ]] || {
			echo "Aborted. Install the packages above and re-run." >&2
			exit 1
		}
	fi

	install_distro_packages "${unique_install[@]}"

	for cmd in "${missing[@]}"; do
		if ! command -v "$cmd" >/dev/null 2>&1; then
			echo "ERROR: '${cmd}' still not on PATH after install." >&2
			exit 1
		fi
	done
}

image_needs_xz() {
	local image=$1
	case "$image" in
		*.xz|*.txz) return 0 ;;
		*) return 1 ;;
	esac
}

ensure_flash_toolchain() {
	local image=${1:-}
	local -a cmds=(dd lsblk findmnt)
	if [[ -n "$image" ]] && image_needs_xz "$image"; then
		cmds+=(xz)
		command -v pv >/dev/null 2>&1 || {
			if [[ "${ROCKSTOR_FLASH_AUTO_INSTALL_DEPS:-0}" == 1 || "${ASSUME_YES}" == 1 ]]; then
				ensure_commands pv
			else
				echo "Optional: 'pv' not found (install for decompression progress during .xz flash)."
				read -r -p "Install pv now? [y/N] " answer
				if [[ "$answer" == [yY] || "$answer" == [yY][eE][sS] ]]; then
					ensure_commands pv
				fi
			fi
		}
	fi
	ensure_commands "${cmds[@]}"
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

ensure_flash_toolchain ""

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
	local repo_root flash_validate apply_uboot
	repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
	flash_validate="${repo_root}/scripts/validate-hc4-raw-uboot.sh"
	apply_uboot="${repo_root}/scripts/apply-uboot-odroid-hc4-to-image.sh"
	if [[ "${ROCKSTOR_FLASH_VALIDATE_UBOOT:-1}" == 1 && -x "$flash_validate" ]]; then
		if ! "$flash_validate" "$dev" 2>/dev/null; then
			echo "WARNING: Armbian U-Boot not detected on ${dev} after flash." >&2
			echo "         Kiwi images built before the U-Boot-on-.raw fix need a post-flash U-Boot write." >&2
			if [[ -x "$apply_uboot" ]]; then
				if [[ "${ASSUME_YES}" == 1 ]]; then
					"$apply_uboot" "$dev"
				else
					read -r -p "Write U-Boot to ${dev} now? [y/N] " answer
					if [[ "$answer" == [yY] || "$answer" == [yY][eE][sS] ]]; then
						"$apply_uboot" "$dev"
					fi
				fi
			fi
		else
			echo "U-Boot layout verified on ${dev}."
		fi
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

ensure_flash_toolchain "$IMAGE_FILE"

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
