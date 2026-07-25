#!/usr/bin/env bash
# Build Linux-facing ODROID-HC4 DTB for FAT /boot (extlinux "fdt" line).
#
# U-Boot and upstream DT use amlogic,meson-sm1-mmc for the SD/MMC blocks, but
# openSUSE kernel-default's meson_gx_mmc only binds gx/gxl/gxm/gxbb/axg compatibles.
# Without an explicit fdt= on extlinux, the board may also boot with a mismatched
# embedded DT (wrong model, no mmcblk). We ship a DTB derived from Armbian U-Boot's
# meson-sm1-odroid-hc4 blob with SD/eMMC nodes retargeted to meson-gxl-mmc.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${1:-${REPO_ROOT}/root/boot/odroid-hc4.dtb}"
UBOOT_DTB_IMG="${ROCKSTOR_HC4_UBOOT_DTB_IMG:-${REPO_ROOT}/.build/uboot-odroid-hc4-fetch/extract-armbian/usr/lib/linux-u-boot-current-odroidhc4/u-boot-dtb.img}"

if [[ ! -f "$UBOOT_DTB_IMG" ]]; then
	echo "build-hc4-linux-dtb: missing ${UBOOT_DTB_IMG} (run scripts/fetch-uboot-odroid-hc4.sh)" >&2
	exit 1
fi

if ! command -v fdtput >/dev/null 2>&1; then
	echo "build-hc4-linux-dtb: need fdtput (device-tree-compiler package)" >&2
	exit 1
fi

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

python3 - "$UBOOT_DTB_IMG" "$tmpdir/source.dtb" <<'PY'
import struct, sys
src, out = sys.argv[1], sys.argv[2]
data = open(src, "rb").read()
magic = struct.pack(">I", 0xD00DFEED)
idx = data.find(magic)
if idx < 0:
    sys.exit("no FDT in u-boot-dtb.img")
size = struct.unpack(">I", data[idx + 4 : idx + 8])[0]
open(out, "wb").write(data[idx : idx + size])
PY

work="${tmpdir}/patched.dtb"
cp "$tmpdir/source.dtb" "$work"

for node in /soc/mmc@ffe03000 /soc/mmc@ffe05000; do
	if fdtget "$work" "$node" compatible &>/dev/null; then
		fdtput -t s "$work" "$node" compatible "amlogic,meson-gxl-mmc"
	fi
done

mkdir -p "$(dirname "$DEST")"
cp "$work" "$DEST"
echo "build-hc4-linux-dtb: wrote ${DEST} (mmc compat -> meson-gxl-mmc for meson_gx_mmc)"
