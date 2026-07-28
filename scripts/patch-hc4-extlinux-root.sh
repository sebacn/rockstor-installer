#!/usr/bin/env bash
# Set root= and rd.luks.uuid= in HC4 extlinux.conf from the built disk (plain or LUKS ROOT).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
	echo "Usage: $0 /path/to/extlinux.conf /dev/loop0|/dev/mapper/loop0p3" >&2
	exit 1
}

[[ $# -eq 2 ]] || usage
CONF=$1
DISK_OR_PART=$2
[[ -f "$CONF" ]] || { echo "Not a file: $CONF" >&2; exit 1; }

run_root() {
	if [[ "$(id -u)" -eq 0 ]]; then
		"$@"
	else
		sudo "$@"
	fi
}

hc4_p3_partition() {
	local disk=$1 base cand
	if [[ -b "$disk" ]] && [[ "$(basename "$disk")" =~ p3$ ]]; then
		echo "$disk"
		return 0
	fi
	base=$(basename "$disk")
	for cand in \
		"${disk}p3" \
		"/dev/mapper/${base}p3" \
		"/dev/${base}p3"; do
		if [[ -b "$cand" ]]; then
			echo "$cand"
			return 0
		fi
	done
	return 1
}

partition_type() {
	run_root blkid -s TYPE -o value "$1" 2>/dev/null || true
}

hc4_btrfs_root_device_plain() {
	local disk=$1 p3 cand base
	p3=$(hc4_p3_partition "$disk") || return 1
	if run_root blkid -s LABEL -o value "$p3" 2>/dev/null | grep -qx ROOT; then
		echo "$p3"
		return 0
	fi
	base=$(basename "$disk")
	for cand in \
		"${disk}p3" \
		"/dev/mapper/${base}p3" \
		"/dev/${base}p3"; do
		if [[ -b "$cand" ]] && run_root blkid -s LABEL -o value "$cand" 2>/dev/null | grep -qx ROOT; then
			echo "$cand"
			return 0
		fi
	done
	run_root blkid -t LABEL=ROOT -o device "$disk" 2>/dev/null | head -1
}

LUKS_UUID=""
P3=$(hc4_p3_partition "$DISK_OR_PART" || true)
if [[ -n "$P3" && "$(partition_type "$P3")" == crypto_LUKS ]]; then
	LUKS_UUID=$(run_root blkid -s UUID -o value "$P3")
fi

MAPPER_OPEN=""
cleanup() {
	if [[ -n "$MAPPER_OPEN" ]]; then
		run_root cryptsetup luksClose "$MAPPER_OPEN" 2>/dev/null || true
	fi
}
trap cleanup EXIT

ROOT_DEV=""
if [[ -n "$P3" && "$(partition_type "$P3")" == crypto_LUKS ]]; then
	key_file=$("${REPO_ROOT}/scripts/hc4-luks-key-file.sh")
	MAPPER_OPEN="rockstor-hc4-patch-$$"
	run_root cryptsetup luksOpen --key-file "$key_file" "$P3" "$MAPPER_OPEN"
	ROOT_DEV=$(run_root blkid -t LABEL=ROOT -o device "/dev/mapper/${MAPPER_OPEN}" 2>/dev/null | head -1)
else
	ROOT_DEV=$(hc4_btrfs_root_device_plain "$DISK_OR_PART" || true)
fi

[[ -n "$ROOT_DEV" && -b "$ROOT_DEV" ]] || {
	echo "patch-hc4-extlinux-root: could not find btrfs ROOT on ${DISK_OR_PART}" >&2
	exit 1
}

ROOT_UUID=$(run_root blkid -s UUID -o value "$ROOT_DEV")
ROOT_LABEL=$(run_root blkid -s LABEL -o value "$ROOT_DEV" 2>/dev/null || true)
if [[ -z "$ROOT_UUID" ]]; then
	echo "patch-hc4-extlinux-root: no UUID on ${ROOT_DEV}" >&2
	exit 1
fi

if [[ "$ROOT_LABEL" == ROOT ]]; then
	ROOT_SPEC="LABEL=ROOT"
else
	ROOT_SPEC="UUID=${ROOT_UUID}"
fi

patch_one_append() {
	local line=$1
	line=$(sed -E 's/[[:space:]]+rd\.luks\.uuid=[^[:space:]]+//g' <<<"$line")
	if [[ -n "$LUKS_UUID" ]]; then
		line="${line} rd.luks.uuid=${LUKS_UUID}"
	fi
	line=$(sed -E "s/root=(UUID=[^[:space:]]+|LABEL=[^[:space:]]+)/root=${ROOT_SPEC}/g" <<<"$line")
	printf '%s\n' "$line"
}

TMP=$(mktemp)
while IFS= read -r line || [[ -n "$line" ]]; do
	if [[ "$line" =~ ^[[:space:]]*append[[:space:]] ]]; then
		patch_one_append "$line"
	else
		printf '%s\n' "$line"
	fi
done <"$CONF" >"$TMP"
mv -f "$TMP" "$CONF"

if [[ -n "$LUKS_UUID" ]]; then
	echo "patch-hc4-extlinux-root: set root=${ROOT_SPEC} rd.luks.uuid=${LUKS_UUID} (LUKS ${P3}, btrfs ${ROOT_DEV})"
else
	echo "patch-hc4-extlinux-root: set root=${ROOT_SPEC} (from ${ROOT_DEV} UUID=${ROOT_UUID})"
fi
