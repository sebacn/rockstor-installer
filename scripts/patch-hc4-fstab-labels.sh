#!/usr/bin/env bash
# Use kiwi partition labels in /etc/fstab (HC4: BOOT, SWAP, ROOT) instead of UUIDs.
# Survives mkfs.vfat/mkswap in edit_boot_install and migrate helpers without fstab drift.
set -euo pipefail

usage() {
	echo "Usage: $0 /path/to/fstab" >&2
	exit 1
}

[[ $# -eq 1 ]] || usage
FSTAB=$1
[[ -f "$FSTAB" ]] || { echo "Not a file: $FSTAB" >&2; exit 1; }

TMP=$(mktemp)
awk '
BEGIN { changed = 0 }
/^[[:space:]]*#/ || /^[[:space:]]*$/ { print; next }
{
	line = $0
	if (line ~ /[[:space:]]swap[[:space:]]+swap([[:space:]]|$)/ || line ~ /[[:space:]]none[[:space:]]+swap([[:space:]]|$)/) {
		sub(/^[^[:space:]]+/, "LABEL=SWAP", line)
		if (line != $0) changed = 1
		print line
		next
	}
	if (line ~ /[[:space:]]\/boot[[:space:]]+vfat([[:space:]]|$)/) {
		sub(/^[^[:space:]]+/, "LABEL=BOOT", line)
		if (line != $0) changed = 1
		print line
		next
	}
	if (line ~ /[[:space:]]\/[[:space:]]+btrfs([[:space:]]|$)/) {
		sub(/^[^[:space:]]+/, "LABEL=ROOT", line)
		if (line != $0) changed = 1
		print line
		next
	}
	print
}
END { if (changed) print "patch-hc4-fstab-labels: converted UUID entries to LABEL=BOOT|SWAP|ROOT" > "/dev/stderr" }
' "$FSTAB" >"$TMP"
mv -f "$TMP" "$FSTAB"
