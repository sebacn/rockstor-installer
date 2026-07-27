#!/usr/bin/env bash
# Verify FAT /boot extlinux root= matches the ROOT btrfs partition on a HC4 .raw or block device.
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
	[[ -n "${mnt:-}" && -d "$mnt" ]] && run_root umount "$mnt" 2>/dev/null || true
	[[ -n "${mnt:-}" && -d "$mnt" ]] && rmdir "$mnt" 2>/dev/null || true
	[[ -n "${loop:-}" && -b "$loop" ]] && run_root kpartx -d "$loop" 2>/dev/null || true
	[[ -n "${loop:-}" && -b "$loop" ]] && run_root losetup -d "$loop" 2>/dev/null || true
}
trap cleanup EXIT

loop=""
mnt=""
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

root_uuid=$(run_root blkid -s UUID -o value "$root" 2>/dev/null || true)
root_label=$(run_root blkid -s LABEL -o value "$root" 2>/dev/null || true)

ok=0
if grep -q 'root=LABEL=ROOT' <<<"$append_line"; then
	if [[ "$root_label" == ROOT ]]; then
		ok=1
	else
		label_dev=$(run_root blkid -L ROOT -o device 2>/dev/null | head -1 || true)
		if [[ -n "$label_dev" && -b "$label_dev" ]]; then
			rn=$(run_root readlink -f "$root" 2>/dev/null || echo "$root")
			ln=$(run_root readlink -f "$label_dev" 2>/dev/null || echo "$label_dev")
			[[ "$rn" == "$ln" ]] && ok=1
		fi
	fi
elif [[ -n "$root_uuid" ]] && grep -q "root=UUID=${root_uuid}" <<<"$append_line"; then
	ok=1
fi

if (( ok )); then
	echo "validate-hc4-extlinux-root: OK (${root} UUID=${root_uuid} matches extlinux)"
	exit 0
fi

echo "validate-hc4-extlinux-root: ERROR: extlinux root= does not match ${root} (UUID=${root_uuid} LABEL=${root_label})" >&2
echo "  extlinux: ${append_line}" >&2
exit 1
