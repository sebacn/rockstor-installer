#!/usr/bin/env bash
# Build mainline U-Boot for ODROID-HC4 and sign with LibreELEC amlogic-boot-fip.
# See: https://github.com/u-boot/u-boot/blob/master/doc/board/amlogic/odroid-hc4.rst
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UBOOT_TAG="${ROCKSTOR_UBOOT_TAG:-v2026.01}"
WORK_DIR="${ROCKSTOR_UBOOT_WORK:-${REPO_ROOT}/.build/uboot-odroid-hc4}"
OUT_BIN="${REPO_ROOT}/root/boot/u-boot.bin"

if command -v aarch64-none-elf-gcc >/dev/null 2>&1; then
    export CROSS_COMPILE="${CROSS_COMPILE:-aarch64-none-elf-}"
elif command -v aarch64-linux-gnu-gcc >/dev/null 2>&1; then
    export CROSS_COMPILE="${CROSS_COMPILE:-aarch64-linux-gnu-}"
else
    echo "build-uboot-odroid-hc4: need aarch64-none-elf- or aarch64-linux-gnu- cross toolchain" >&2
    exit 1
fi

for cmd in git make; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "build-uboot-odroid-hc4: missing required command: $cmd" >&2
        exit 1
    fi
done

host_arch="$(uname -m)"
if [ "$host_arch" != x86_64 ]; then
    if ! command -v qemu-x86_64 >/dev/null 2>&1; then
        echo "build-uboot-odroid-hc4: on ${host_arch}, qemu-x86_64 is required for aml_encrypt_g12a" >&2
        echo "  (e.g. openSUSE: qemu-linux-user, Debian/Ubuntu: qemu-user-static)" >&2
        exit 1
    fi
    if [ -d /usr/x86_64-linux-gnu ] && [ -z "${QEMU_LD_PREFIX:-}" ]; then
        export QEMU_LD_PREFIX=/usr/x86_64-linux-gnu
    fi
fi

mkdir -p "$WORK_DIR" "$(dirname "$OUT_BIN")"
uboot_src="${WORK_DIR}/u-boot"
fip_src="${WORK_DIR}/amlogic-boot-fip"
fip_out="${WORK_DIR}/fip-out"

if [ ! -d "$uboot_src/.git" ]; then
    git clone --depth 1 --branch "$UBOOT_TAG" https://github.com/u-boot/u-boot.git "$uboot_src"
else
    git -C "$uboot_src" fetch --depth 1 origin "refs/tags/${UBOOT_TAG}:refs/tags/${UBOOT_TAG}" 2>/dev/null || true
    git -C "$uboot_src" checkout -f "$UBOOT_TAG"
fi

make -C "$uboot_src" odroid-hc4_defconfig
make -C "$uboot_src" -j"$(nproc 2>/dev/null || echo 4)"

bl33="${uboot_src}/u-boot.bin"
if [ ! -f "$bl33" ]; then
    echo "build-uboot-odroid-hc4: U-Boot build did not produce u-boot.bin" >&2
    exit 1
fi

if [ ! -d "$fip_src/.git" ]; then
    git clone --depth 1 https://github.com/LibreELEC/amlogic-boot-fip.git "$fip_src"
fi

rm -rf "$fip_out"
mkdir -p "$fip_out"
(
    cd "$fip_src"
    ./build-fip.sh odroid-hc4 "$bl33" "$fip_out"
)

signed="${fip_out}/u-boot.bin"
if [ ! -f "$signed" ]; then
    echo "build-uboot-odroid-hc4: FIP step did not produce ${signed}" >&2
    exit 1
fi

install -m 0644 "$signed" "$OUT_BIN"
echo "build-uboot-odroid-hc4: installed ${OUT_BIN}"
