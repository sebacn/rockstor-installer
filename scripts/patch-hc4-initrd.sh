#!/usr/bin/env bash
# Patches HC4 FAT /boot initrd: Kiwi oem-resize-once + serial emergency diagnostics.
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
	echo "initrd: kiwi_oemresizeonce already true"
else
	sed -i "s/^kiwi_oemresizeonce=.*/kiwi_oemresizeonce='true'/" "$PROFILE"
	grep -q "kiwi_oemresizeonce='true'" "$PROFILE" || echo "kiwi_oemresizeonce='true'" >>"$PROFILE"
	echo "initrd: set kiwi_oemresizeonce=true"
fi

HOOK_DIR="$WORK/var/lib/dracut/hooks/emergency"
mkdir -p "$HOOK_DIR"
cat >"$HOOK_DIR/99-rockstor-serial-diagnostics.sh" <<'EOF'
#!/bin/sh
# Dracut emergency only prints the rdsosreport banner on serial; dump full files here.
for _f in /run/initramfs/rdsosreport.txt /run/initramfs/log/boot.kiwi /run/initramfs/init.log; do
	[ -f "$_f" ] || continue
	printf '\n===== rockstor initrd: %s =====\n' "$_f" > /dev/console
	cat "$_f" > /dev/console
done
EOF
chmod 0755 "$HOOK_DIR/99-rockstor-serial-diagnostics.sh"
echo "initrd: installed emergency serial diagnostics hook"

TMP_OUT=$(mktemp)
(cd "$WORK" && find . | cpio -o -H newc --quiet | zstd -19 -T0 -f -q -o "$TMP_OUT")
mv -f "$TMP_OUT" "$OUT"
echo "Wrote ${OUT}"
