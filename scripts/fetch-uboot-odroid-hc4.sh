#!/usr/bin/env bash
# Fetch pre-built U-Boot for ODROID-HC4 (default: openSUSE RPM fits before FAT @ LBA 2048;
# optional Armbian deb is larger — use only if boot partition starts at LBA 8192+).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="${ROCKSTOR_UBOOT_SOURCE:-opensuse}"
FETCH_DIR="${REPO_ROOT}/.build/uboot-odroid-hc4-fetch"
DEST="${REPO_ROOT}/root/boot/u-boot.bin"
STYLE_FILE="${REPO_ROOT}/root/boot/.uboot-install-style"

mkdir -p "${FETCH_DIR}" "${REPO_ROOT}/root/boot"

fetch_opensuse() {
	local rpm_url="${RPM_URL:-https://cdn.opensuse.org/ports/aarch64/tumbleweed/repo/oss/aarch64/u-boot-odroid-c4-2026.01-1.3.aarch64.rpm}"
	local rpm_path="${FETCH_DIR}/$(basename "${rpm_url}")"
	if [[ ! -f "${rpm_path}" ]]; then
		echo "Downloading ${rpm_url} ..." >&2
		curl -fsSL -o "${rpm_path}" "${rpm_url}"
	fi
	local extract_dir="${FETCH_DIR}/extract-opensuse"
	rm -rf "${extract_dir}"
	mkdir -p "${extract_dir}"
	extract_rpm_payload "${rpm_path}" "${extract_dir}"
	printf '%s\n' "${extract_dir}/boot/u-boot.bin"
}

fetch_armbian() {
	local mirror="${ARMBIAN_UBOOT_MIRROR:-https://fi.mirror.armbian.de/beta/pool/main/l/linux-u-boot-odroidhc4-current}"
	local deb_url="${ARMBIAN_UBOOT_DEB_URL:-}"
	if [[ -z "${deb_url}" ]]; then
		echo "Resolving latest linux-u-boot-odroidhc4-current .deb from ${mirror} ..." >&2
		deb_url="$(curl -fsSL "${mirror}/" | grep -oE 'linux-u-boot-odroidhc4-current_[^"]+\.deb' | tail -1)"
		deb_url="${mirror}/${deb_url}"
	fi
	local deb_path="${FETCH_DIR}/$(basename "${deb_url}")"
	if [[ ! -f "${deb_path}" ]]; then
		echo "Downloading ${deb_url} ..." >&2
		curl -fsSL -o "${deb_path}" "${deb_url}"
	fi
	local extract_dir="${FETCH_DIR}/extract-armbian"
	rm -rf "${extract_dir}"
	mkdir -p "${extract_dir}"
	dpkg-deb -x "${deb_path}" "${extract_dir}"
	printf '%s\n' "${extract_dir}/usr/lib/linux-u-boot-current-odroidhc4/u-boot.bin"
}

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

uboot_src=""
case "${SOURCE}" in
	opensuse)
		uboot_src="$(fetch_opensuse)"
		echo "opensuse" >"${STYLE_FILE}"
		;;
	armbian)
		command -v dpkg-deb >/dev/null 2>&1 || {
			echo "fetch-uboot-odroid-hc4: armbian source needs dpkg-deb" >&2
			exit 1
		}
		uboot_src="$(fetch_armbian)"
		echo "armbian" >"${STYLE_FILE}"
		;;
	*)
		echo "fetch-uboot-odroid-hc4: unknown ROCKSTOR_UBOOT_SOURCE=${SOURCE} (use opensuse or armbian)" >&2
		exit 1
		;;
esac

if [[ ! -f "${uboot_src}" ]]; then
	echo "fetch-uboot-odroid-hc4: missing ${uboot_src}" >&2
	exit 1
fi

install -m 0644 "${uboot_src}" "${DEST}"
echo "fetch-uboot-odroid-hc4: installed ${DEST} (source=${SOURCE})"

if command -v strings >/dev/null 2>&1; then
	strings "${DEST}" | grep -E 'U-Boot 20[0-9]{2}\.[0-9]{2}' | head -1 || strings "${DEST}" | grep -m1 'U-Boot' || true
fi
