#!/bin/bash
# Post-process OEM disk image for ODROID-HC4 (Amlogic S905X3, MBR + U-Boot).
# Layout follows Hardkernel / openSUSE JeOS odroid practice: U-Boot at sector 1,
# DOS partition table, FAT /boot (kiwi bootpartition), btrfs root for Rockstor.
# Ref: https://wiki.odroid.com/odroid-hc4/software/partition_table
set -euxo pipefail

diskname=$1
devname="$2"
loopname="${devname%*p?}"
loopdev=${loopname#/dev/mapper/*}

# Kiwi runs: cd <image-root> && bash .../image/edit_boot_install.sh <disk> <boot-partition>
image_root="$(pwd)"

#==========================================
# Locate pre-built openSUSE u-boot-odroid-c4 (RPM in image) or kiwi overlay root/boot/u-boot.bin
#------------------------------------------
uboot_bin=""
for candidate in \
    "${image_root}/boot/u-boot.bin" \
    "${image_root}/usr/share/u-boot/odroid-c4/u-boot.bin"; do
    if [ -f "$candidate" ]; then
        uboot_bin=$candidate
        break
    fi
done
if [ -z "$uboot_bin" ] && command -v rpm >/dev/null 2>&1 && rpm --root "$image_root" -q u-boot-odroid-c4 >/dev/null 2>&1; then
    uboot_bin=$(rpm --root "$image_root" -ql u-boot-odroid-c4 | grep -E '/u-boot\.bin$' | head -1 || true)
fi

#==========================================
# Ensure DOS (MBR) partition table if kiwi left a protective GPT header
# (before writing U-Boot at sector 1 — gdisk would overwrite it)
#------------------------------------------
if command -v gdisk >/dev/null 2>&1 && gdisk -l "$loopdev" 2>/dev/null | grep -qi 'GPT'; then
    echo "ODROID HC4: converting protective GPT to MBR for legacy boot ROM"
    cat > gdisk.tmp <<-'EOF'
		x
		r
		g
		w
		y
	EOF
    dd if="$loopdev" of=mbrid.bin bs=1 skip=440 count=4
    gdisk "$loopdev" < gdisk.tmp
    dd of="$loopdev" if=mbrid.bin bs=1 seek=440 count=4
    rm -f mbrid.bin gdisk.tmp
fi

# Install U-Boot on whole disk (Armbian / openSUSE SD images: 442 bytes @0 + payload @sector 1).
#------------------------------------------
if [ -n "$uboot_bin" ] && [ -f "$uboot_bin" ]; then
    echo "ODROID HC4: writing U-Boot from ${uboot_bin} to ${loopdev}"
    dd if="$uboot_bin" of="$loopdev" conv=fsync,notrunc bs=1 count=442
    dd if="$uboot_bin" of="$loopdev" conv=fsync,notrunc bs=512 skip=1 seek=1
else
    echo "ODROID HC4: WARNING: u-boot.bin not found; image may not boot on hardware" >&2
fi
