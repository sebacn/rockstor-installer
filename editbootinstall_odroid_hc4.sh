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
# Locate Armbian pre-built U-Boot (kiwi overlay root/boot/u-boot.bin from fetch-uboot-odroid-hc4.sh)
#------------------------------------------
uboot_bin=""
for candidate in \
    "${image_root}/boot/u-boot.bin"; do
    if [ -f "$candidate" ]; then
        uboot_bin=$candidate
        break
    fi
done

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

# U-Boot image extends past LBA 2048 and destroys kiwi's FAT /boot; recreate it now.
#------------------------------------------
boot_part="${devname}"
if [ -b "${boot_part}" ]; then
    echo "ODROID HC4: recreating FAT boot on ${boot_part} after U-Boot install"
    mkfs.vfat -F 32 -n BOOT "${boot_part}"
    boot_mnt=$(mktemp -d)
    mount "${boot_part}" "${boot_mnt}"
    trap 'umount "${boot_mnt}" 2>/dev/null; rmdir "${boot_mnt}" 2>/dev/null' EXIT
    for f in Image initrd; do
        if [ -f "${image_root}/boot/${f}" ]; then
            cp -a "${image_root}/boot/${f}" "${boot_mnt}/"
        fi
    done
    for f in "${image_root}"/boot/Image-* "${image_root}"/boot/initrd-*; do
        [ -f "$f" ] || continue
        base=$(basename "$f")
        [ "$base" = "Image" ] || [ "$base" = "initrd" ] && continue
        cp -a "$f" "${boot_mnt}/"
    done
    if [ -f "${image_root}/boot/extlinux/extlinux.conf" ]; then
        mkdir -p "${boot_mnt}/extlinux"
        cp -a "${image_root}/boot/extlinux/extlinux.conf" "${boot_mnt}/extlinux/"
    fi
    umount "${boot_mnt}"
    rmdir "${boot_mnt}"
    trap - EXIT
    sync
else
    echo "ODROID HC4: WARNING: boot partition ${boot_part} not found; FAT /boot not rebuilt" >&2
fi
