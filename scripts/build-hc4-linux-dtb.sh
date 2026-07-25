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

# gpio-regulator-tf-io (vqmmc) chains to regulator-vcc-5v whose GPIO probe can fail
# (-EPERM) and defer ffe05000.mmc forever. Keep vmmc/vqmmc on the MMC node.
if fdtget "$work" /regulator-vcc-5v compatible &>/dev/null; then
	fdtput -d "$work" /regulator-vcc-5v gpio 2>/dev/null || true
fi
if fdtget "$work" /gpio-regulator-tf-io compatible &>/dev/null; then
	fdtput -d "$work" /gpio-regulator-tf-io vin-supply 2>/dev/null || true
fi

# LAN (RTL8211F on RGMII): MDIO mux fails when PHY reset GPIO or p12v regulator GPIO
# probe as -EPERM; end0 then has no PHY. Drop redundant resets / always-on GPIO enables.
for node in /regulator-p12v-0 /regulator-p12v-1; do
	if fdtget "$work" "$node" compatible &>/dev/null; then
		fdtput -d "$work" "$node" gpio 2>/dev/null || true
	fi
done
EXT_PHY="/soc/bus@ff600000/mdio-multiplexer@4c000/mdio@0/ethernet-phy@0"
if fdtget "$work" "$EXT_PHY" reg &>/dev/null; then
	fdtput -d "$work" "$EXT_PHY" reset-gpios 2>/dev/null || true
fi
INT_MDIO="/soc/bus@ff600000/mdio-multiplexer@4c000/mdio@1"
if fdtget "$work" "$INT_MDIO" reg &>/dev/null; then
	fdtput -t s "$work" "$INT_MDIO" status "disabled"
fi
ETHMAC="/soc/ethernet@ff3f0000"
if fdtget "$work" "$ETHMAC" compatible &>/dev/null; then
	fdtput -d "$work" "$ETHMAC" snps,reset-gpio 2>/dev/null || true
	fdtput -d "$work" "$ETHMAC" snps,reset-delays-us 2>/dev/null || true
	fdtput -d "$work" "$ETHMAC" snps,reset-active-low 2>/dev/null || true
fi

mkdir -p "$(dirname "$DEST")"
cp "$work" "$DEST"
echo "build-hc4-linux-dtb: wrote ${DEST} (mmc compat -> meson-gxl-mmc for meson_gx_mmc)"
