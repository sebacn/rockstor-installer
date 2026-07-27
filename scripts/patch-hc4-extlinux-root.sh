#!/usr/bin/env bash
# Set root= in HC4 extlinux.conf from the actual btrfs ROOT partition on the disk image.
set -euo pipefail

usage() {
	echo "Usage: $0 /path/to/extlinux.conf /dev/mapper/loop0p3|/dev/loop0" >&2
	exit 1
}

[[ $# -eq 2 ]] || usage
CONF=$1
DISK_OR_PART=$2
[[ -f "$CONF" ]] || { echo "Not a file: $CONF" >&2; exit 1; }

hc4_root_partition() {
	local disk=$1
	local base p cand
	if [[ -b "$disk" ]] && blkid -s LABEL -o value "$disk" 2>/dev/null | grep -qx ROOT; then
		echo "$disk"
		return 0
	fi
	base=$(basename "$disk")
	for cand in \
		"${disk}p3" \
		"/dev/mapper/${base}p3" \
		"/dev/${base}p3"; do
		if [[ -b "$cand" ]] && blkid -s LABEL -o value "$cand" 2>/dev/null | grep -qx ROOT; then
			echo "$cand"
			return 0
		fi
	done
	blkid -t LABEL=ROOT -o device "$disk" 2>/dev/null | head -1
}

ROOT_DEV=$(hc4_root_partition "$DISK_OR_PART")
[[ -n "$ROOT_DEV" && -b "$ROOT_DEV" ]] || {
	echo "patch-hc4-extlinux-root: could not find btrfs ROOT partition on ${DISK_OR_PART}" >&2
	exit 1
}

ROOT_UUID=$(blkid -s UUID -o value "$ROOT_DEV")
ROOT_LABEL=$(blkid -s LABEL -o value "$ROOT_DEV" || true)
if [[ -z "$ROOT_UUID" ]]; then
	echo "patch-hc4-extlinux-root: no UUID on ${ROOT_DEV}" >&2
	exit 1
fi

# Prefer LABEL=ROOT (kiwi default); dracut/systemd resolve it reliably on HC4 SD.
if [[ "$ROOT_LABEL" == ROOT ]]; then
	ROOT_SPEC="LABEL=ROOT"
else
	ROOT_SPEC="UUID=${ROOT_UUID}"
fi

TMP=$(mktemp)
sed -E "s/root=(UUID=[^ ]+|LABEL=[^ ]+)/root=${ROOT_SPEC}/g" "$CONF" >"$TMP"
mv -f "$TMP" "$CONF"
echo "patch-hc4-extlinux-root: set root=${ROOT_SPEC} (from ${ROOT_DEV} UUID=${ROOT_UUID})"
