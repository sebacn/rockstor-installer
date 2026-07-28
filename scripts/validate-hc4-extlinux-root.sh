#!/usr/bin/env bash
# Verify FAT /boot extlinux root= (and rd.luks.uuid=) match ROOT on a HC4 .raw or block device.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE=${1:-}
[[ -n "$IMAGE" ]] || { echo "Usage: $0 /path/to/image.raw|/dev/sdX" >&2; exit 1; }

run_root() {
	if [[ "$(id -u)" -eq 0 ]]; then
		"$@"
	else
		sudo "$@"
	fi
}

cleanup() {
	[[ -n "${mapper_open:-}" ]] && run_root cryptsetup luksClose "$mapper_open" 2>/dev/null || true
	[[ -n "${mnt:-}" && -d "$mnt" ]] && run_root umount "$mnt" 2>/dev/null || true
	[[ -n "${mnt:-}" && -d "$mnt" ]] && rmdir "$mnt" 2>/dev/null || true
	[[ -n "${loop:-}" && -b "$loop" ]] && run_root kpartx -d "$loop" 2>/dev/null || true
	[[ -n "${loop:-}" && -b "$loop" ]] && run_root losetup -d "$loop" 2>/dev/null || true
}
trap cleanup EXIT

loop=""
mnt=""
mapper_open=""
if [[ -f "$IMAGE" ]]; then
	loop=$(run_root losetup -fP --show "$IMAGE")
	run_root kpartx -av "$loop" >/dev/null 2>&1
	run_root partprobe "$loop" 2>/dev/null || true
	run_root udevadm settle 2>/dev/null || true
	sleep 1
	disk="$loop"
	boot="/dev/mapper/$(basename "$loop")p1"
	root="/dev/mapper/$(basename "$loop")p3"
elif [[ -b "$IMAGE" ]]; then
	disk="$IMAGE"
	case "$disk" in
	*/mmcblk*) boot="${disk}p1"; root="${disk}p3" ;;
	*) boot="${disk}1"; root="${disk}3" ;;
	esac
else
	echo "validate-hc4-extlinux-root: not a file or block device: $IMAGE" >&2
	exit 1
fi

[[ -b "$boot" && -b "$root" ]] || {
	echo "validate-hc4-extlinux-root: missing boot or root partition on $IMAGE" >&2
	exit 1
}

mnt=$(mktemp -d)
run_root mount "$boot" "$mnt"
conf="${mnt}/extlinux/extlinux.conf"
[[ -f "$conf" ]] || {
	echo "validate-hc4-extlinux-root: missing ${conf}" >&2
	exit 1
}

append_line=$(grep -E '^[[:space:]]*append ' "$conf" | head -1 || true)
[[ -n "$append_line" ]] || {
	echo "validate-hc4-extlinux-root: no append line in extlinux.conf" >&2
	exit 1
}

root_part="$root"
root_type=$(run_root blkid -s TYPE -o value "$root_part" 2>/dev/null || true)
luks_uuid=""
if [[ "$root_type" == crypto_LUKS ]]; then
	luks_uuid=$(run_root blkid -s UUID -o value "$root_part")
	if ! grep -q "rd.luks.uuid=${luks_uuid}" <<<"$append_line"; then
		echo "validate-hc4-extlinux-root: ERROR: missing rd.luks.uuid=${luks_uuid} in extlinux" >&2
		echo "  extlinux: ${append_line}" >&2
		exit 1
	fi
	key_file=$("${REPO_ROOT}/scripts/hc4-luks-key-file.sh")
	mapper_open="rockstor-hc4-validate-$$"
	run_root cryptsetup luksOpen --key-file "$key_file" "$root_part" "$mapper_open"
	root_part="/dev/mapper/${mapper_open}"
fi

root_uuid=$(run_root blkid -s UUID -o value "$root_part" 2>/dev/null || true)
root_label=$(run_root blkid -s LABEL -o value "$root_part" 2>/dev/null || true)

ok=0
if grep -q 'root=LABEL=ROOT' <<<"$append_line"; then
	if [[ "$root_label" == ROOT ]]; then
		ok=1
	else
		label_dev=$(run_root blkid -L ROOT -o device 2>/dev/null | head -1 || true)
		if [[ -n "$label_dev" && -b "$label_dev" ]]; then
			rn=$(run_root readlink -f "$root_part" 2>/dev/null || echo "$root_part")
			ln=$(run_root readlink -f "$label_dev" 2>/dev/null || echo "$label_dev")
			[[ "$rn" == "$ln" ]] && ok=1
		fi
	fi
elif [[ -n "$root_uuid" ]] && grep -q "root=UUID=${root_uuid}" <<<"$append_line"; then
	ok=1
fi

if (( ok )); then
	if [[ -n "$luks_uuid" ]]; then
		echo "validate-hc4-extlinux-root: OK (LUKS ${root} rd.luks.uuid=${luks_uuid}, btrfs ${root_part})"
	else
		echo "validate-hc4-extlinux-root: OK (${root_part} UUID=${root_uuid} matches extlinux)"
	fi
	exit 0
fi

echo "validate-hc4-extlinux-root: ERROR: extlinux root= does not match ${root_part} (UUID=${root_uuid} LABEL=${root_label})" >&2
echo "  extlinux: ${append_line}" >&2
exit 1
