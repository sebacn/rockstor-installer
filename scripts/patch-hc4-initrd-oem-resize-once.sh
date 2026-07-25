#!/usr/bin/env bash
# Kiwi dracut repart runs on every boot when MBR has free space before p1@8192
# (U-Boot gap). Set kiwi_oemresizeonce in the initrd /.profile so repart runs
# only until the root PARTUUID changes (once per disk layout).
set -euo pipefail

usage() {
	echo "Usage: $0 /path/to/initrd [/path/to/output-initrd]" >&2
	exit 1
}

[[ $# -ge 1 && $# -le 2 ]] || usage
SRC=$1
OUT=${2:-$1}
[[ -f "$SRC" ]] || { echo "Not a file: $SRC" >&2; exit 1; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

set +o pipefail
case "$SRC" in
*.xz) xz -dc "$SRC" | (cd "$WORK" && cpio -idm 2>/dev/null) ;;
*) zstd -dc "$SRC" | (cd "$WORK" && cpio -idm 2>/dev/null) ;;
esac
set -o pipefail

PROFILE="$WORK/.profile"
[[ -f "$PROFILE" ]] || { echo "No /.profile in initrd (not a kiwi dracut image?)" >&2; exit 1; }

if grep -q "kiwi_oemresizeonce='true'" "$PROFILE"; then
	echo "initrd already has kiwi_oemresizeonce=true"
else
	sed -i "s/^kiwi_oemresizeonce=.*/kiwi_oemresizeonce='true'/" "$PROFILE"
	grep -q "kiwi_oemresizeonce='true'" "$PROFILE" || echo "kiwi_oemresizeonce='true'" >>"$PROFILE"
	echo "Patched kiwi_oemresizeonce=true in initrd profile"
fi

TMP_OUT=$(mktemp)
(cd "$WORK" && find . | cpio -o -H newc --quiet | zstd -19 -T0 -f -q -o "$TMP_OUT")
mv -f "$TMP_OUT" "$OUT"
echo "Wrote ${OUT}"
