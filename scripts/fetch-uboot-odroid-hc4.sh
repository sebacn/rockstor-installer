#!/usr/bin/env bash
# Fetch pre-built U-Boot for ODROID-HC4/C4 from openSUSE Tumbleweed (u-boot-odroid-c4 RPM).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RPM_URL="${RPM_URL:-https://cdn.opensuse.org/ports/aarch64/tumbleweed/repo/oss/aarch64/u-boot-odroid-c4-2026.01-1.3.aarch64.rpm}"
FETCH_DIR="${REPO_ROOT}/.build/uboot-odroid-hc4-fetch"
DEST="${REPO_ROOT}/root/boot/u-boot.bin"

mkdir -p "${FETCH_DIR}" "${REPO_ROOT}/root/boot"
RPM_BASENAME="$(basename "${RPM_URL}")"
RPM_PATH="${FETCH_DIR}/${RPM_BASENAME}"

if [[ ! -f "${RPM_PATH}" ]]; then
	echo "Downloading ${RPM_URL} ..."
	curl -fsSL -o "${RPM_PATH}" "${RPM_URL}"
fi

EXTRACT_DIR="${FETCH_DIR}/extract"
rm -rf "${EXTRACT_DIR}"
mkdir -p "${EXTRACT_DIR}"

extract_rpm_payload() {
	local rpm_path=$1 dest=$2
	if command -v bsdtar >/dev/null 2>&1; then
		bsdtar -xf "${rpm_path}" -C "${dest}"
		return 0
	fi
	if command -v rpm2cpio >/dev/null 2>&1 && command -v cpio >/dev/null 2>&1; then
		( cd "${dest}" && rpm2cpio "${rpm_path}" | cpio -idmv )
		return 0
	fi
	if command -v ar >/dev/null 2>&1 && command -v cpio >/dev/null 2>&1; then
		local ar_dir="${dest}/ar"
		mkdir -p "${ar_dir}"
		( cd "${ar_dir}" && ar x "${rpm_path}" )
		local payload
		for payload in "${ar_dir}"/data.zst "${ar_dir}"/data.zstd "${ar_dir}"/data.xz "${ar_dir}"/data.gz; do
			[ -f "${payload}" ] || continue
			case "${payload}" in
				*.zst|*.zstd)
					command -v zstd >/dev/null 2>&1 || continue
					zstd -dc "${payload}" | ( cd "${dest}" && cpio -idmv )
					return 0
					;;
				*.xz)
					xz -dc "${payload}" | ( cd "${dest}" && cpio -idmv )
					return 0
					;;
				*.gz)
					gunzip -c "${payload}" | ( cd "${dest}" && cpio -idmv )
					return 0
					;;
			esac
		done
	fi
	return 1
}

if ! extract_rpm_payload "${RPM_PATH}" "${EXTRACT_DIR}"; then
	echo "fetch-uboot-odroid-hc4: need bsdtar, rpm2cpio+cpio, or ar+cpio+zstd to extract RPM" >&2
	exit 1
fi

UBOOT_SRC="${EXTRACT_DIR}/boot/u-boot.bin"
if [[ ! -f "${UBOOT_SRC}" ]]; then
	echo "fetch-uboot-odroid-hc4: expected boot/u-boot.bin inside RPM" >&2
	exit 1
fi

install -m 0644 "${UBOOT_SRC}" "${DEST}"
echo "fetch-uboot-odroid-hc4: installed ${DEST}"

if command -v strings >/dev/null 2>&1; then
	strings "${DEST}" | grep -E 'U-Boot 20[0-9]{2}\.[0-9]{2}' | head -1 || strings "${DEST}" | grep -m1 'U-Boot' || true
fi
