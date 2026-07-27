#!/usr/bin/env bash
# Grow HC4 MBR partition 3 (btrfs ROOT) and the filesystem into trailing unallocated space.
# Kiwi OEM repart is disabled in HC4 initrd (patch-hc4-initrd.sh); run this on first boot or manually.
set -euo pipefail

MARKER_DIR=/var/lib/rockstor
MARKER_FILE="${MARKER_DIR}/hc4-root-expanded"
ROOT_LABEL=ROOT

usage() {
	echo "Usage: $0 [--oneshot] [/dev/mmcblk0|/dev/sdX]" >&2
	echo "  --oneshot  Skip if ${MARKER_FILE} exists (for systemd)." >&2
	exit 1
}

log() { echo "rockstor-hc4-expand-root: $*"; }

disk_for_mount_source() {
	local src=$1 pk
	src=${src%%\[*}
	[[ -n "$src" && -b "$src" ]] || return 1
	pk=$(lsblk -no PKNAME "$src" 2>/dev/null | head -1)
	if [[ -n "$pk" ]]; then
		echo "/dev/${pk}"
		return 0
	fi
	echo "$src"
}

hc4_partitions() {
	local disk=$1
	case "$disk" in
	*/mmcblk*) echo "${disk}p1" "${disk}p2" "${disk}p3" ;;
	*) echo "${disk}1" "${disk}2" "${disk}3" ;;
	esac
}

unallocated_mib_after_p3() {
	local disk=$1
	parted -s "$disk" unit MiB print free 2>/dev/null | awk '
		/Free Space/ {
			gsub(/MiB/, "", $3)
			size = $3
		}
		END { if (size != "") print size }
	'
}

partition3_needs_grow() {
	local disk=$1 p3_end disk_end
	p3_end=$(parted -s "$disk" unit MiB print 2>/dev/null | awk '$1==3 { gsub(/MiB/, "", $3); print $3 }')
	disk_end=$(parted -s "$disk" unit MiB print 2>/dev/null | awk -F': ' '/^Disk / { gsub(/MiB/, "", $2); print $2 }')
	[[ -n "$p3_end" && -n "$disk_end" ]] || return 0
	awk -v p="$p3_end" -v d="$disk_end" 'BEGIN { exit (p < d - 4) ? 0 : 1 }'
}

expand_btrfs_on_mountpoint() {
	local mnt=$1
	if btrfs filesystem resize max "$mnt"; then
		log "btrfs resized on ${mnt}"
	fi
	if btrfs subvolume list "$mnt" 2>/dev/null | grep -q 'path @/.snapshots/1/snapshot'; then
		btrfs subvolume set-default "$mnt/@/.snapshots/1/snapshot" 2>/dev/null || true
	elif btrfs subvolume list "$mnt" 2>/dev/null | grep -q 'path @'; then
		btrfs subvolume set-default "$mnt/@" 2>/dev/null || true
	fi
}

ONESHOT=0
DISK=""
while [[ $# -gt 0 ]]; do
	case "$1" in
	--oneshot) ONSHOT=1; shift ;;
	-h|--help) usage ;;
	*) DISK=$1; shift ;;
	esac
done

if [[ "${ONESHOT}" -eq 1 && -f "${MARKER_FILE}" ]]; then
	log "already expanded (${MARKER_FILE}); exiting"
	exit 0
fi

if [[ -z "${DISK}" ]]; then
	DISK=$(disk_for_mount_source "$(findmnt -n -o SOURCE / 2>/dev/null || true)" || true)
fi
[[ -n "${DISK}" && -b "${DISK}" ]] || {
	log "ERROR: could not determine block device (pass /dev/mmcblk0)" >&2
	exit 1
}

read -r P1 P2 P3 < <(hc4_partitions "$DISK")
for p in "$P1" "$P2" "$P3"; do
	[[ -b "$p" ]] || {
		log "ERROR: missing HC4 partition ${p}" >&2
		exit 1
	}
done

[[ "$(blkid -s LABEL -o value "$P3" 2>/dev/null || true)" == "${ROOT_LABEL}" ]] || {
	log "ERROR: ${P3} is not LABEL=${ROOT_LABEL}" >&2
	exit 1
}

FREE_MIB=$(unallocated_mib_after_p3 "$DISK" || true)
if ! partition3_needs_grow "$DISK"; then
	log "partition 3 already spans the disk; nothing to do"
	[[ "${ONESHOT}" -eq 1 ]] && mkdir -p "${MARKER_DIR}" && touch "${MARKER_FILE}"
	exit 0
fi

if [[ -n "${FREE_MIB}" && "${FREE_MIB%%.*}" -ge 8 ]]; then
	log "growing partition 3 on ${DISK} (${FREE_MIB} MiB unallocated after p3)"
else
	log "growing partition 3 on ${DISK} to end of disk"
fi
if ! parted -s "$DISK" resizepart 3 100%; then
	log "ERROR: parted resizepart failed on ${DISK}" >&2
	exit 1
fi
partprobe "$DISK" 2>/dev/null || true
sleep 1

ROOT_SRC=$(findmnt -n -o SOURCE / 2>/dev/null || true)
ROOT_SRC=${ROOT_SRC%%\[*}
if [[ "${ROOT_SRC}" == "${P3}" ]] || [[ "${ROOT_SRC}" == /dev/mapper/*"${P3##*/}"* ]]; then
	expand_btrfs_on_mountpoint /
else
	mnt=$(mktemp -d)
	if mount -o rw,subvol=@/.snapshots/1/snapshot "$P3" "$mnt" 2>/dev/null \
		|| mount -o rw "$P3" "$mnt" 2>/dev/null; then
		expand_btrfs_on_mountpoint "$mnt"
		umount "$mnt"
	fi
	rmdir "$mnt" 2>/dev/null || true
fi

mkdir -p "${MARKER_DIR}"
touch "${MARKER_FILE}"
log "done; marker ${MARKER_FILE}"
