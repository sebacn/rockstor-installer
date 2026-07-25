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
# Dracut sources emergency/*.sh; dump diagnostics to serial (ttyAML0) and console.
rockstor_dump_initrd_diag() {
	for _f in /run/initramfs/rdsosreport.txt /run/initramfs/log/boot.kiwi /run/initramfs/init.log; do
		[ -f "$_f" ] || continue
		for _out in /dev/ttyAML0 /dev/console /dev/tty0; do
			[ -c "$_out" ] || continue
			printf '\n===== rockstor initrd: %s =====\n' "$_f" >"$_out"
			cat "$_f" >"$_out"
		done
	done
}
rockstor_dump_initrd_diag
EOF
chmod 0755 "$HOOK_DIR/99-rockstor-serial-diagnostics.sh"
echo "initrd: installed emergency serial diagnostics hook"

PRE_UDEV_DIR="$WORK/var/lib/dracut/hooks/pre-udev"
mkdir -p "$PRE_UDEV_DIR"
cat >"$PRE_UDEV_DIR/99-rockstor-hc4-sd-mmc.sh" <<'EOF'
#!/bin/sh
# HC4 root is on microSD (Amlogic meson-gx-mmc). Kiwi/dracut hostonly builds often
# never modprobe this on real hardware, so root=UUID waits forever with no block devs.
type modprobe >/dev/null 2>&1 || exit 0
for _m in mmc_core meson_gx_mmc mmc_block; do
	modprobe "$_m" 2>/dev/null || true
done
EOF
chmod 0755 "$PRE_UDEV_DIR/99-rockstor-hc4-sd-mmc.sh"
echo "initrd: installed pre-udev HC4 SD/MMC modprobe hook"

REPART_HOOK="$WORK/var/lib/dracut/hooks/pre-mount/20-kiwi-repart-disk.sh"
if [[ -f "$REPART_HOOK" ]]; then
	mv -f "$REPART_HOOK" "${REPART_HOOK}.disabled-by-rockstor-hc4"
	echo "initrd: disabled kiwi-repart pre-mount hook (HC4 uses pre-sized SD layout)"
fi

TMP_OUT=$(mktemp)
(cd "$WORK" && find . | cpio -o -H newc --quiet | zstd -19 -T0 -f -q -o "$TMP_OUT")
mv -f "$TMP_OUT" "$OUT"
echo "Wrote ${OUT}"
