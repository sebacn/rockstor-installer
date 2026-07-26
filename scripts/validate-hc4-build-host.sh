#!/usr/bin/env bash
# Pre-flight checks before Tumbleweed.OdroidHC4 kiwi-ng image build.
# Usage: scripts/validate-hc4-build-host.sh [--docker|--native]
# Env: same ROCKSTOR_* paths as .cursor/run-odroid-hc4-kiwi-build.sh; ROCKSTOR_SKIP_HC4_VALIDATE=1 to skip.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${ROCKSTOR_HC4_BUILD_MODE:-docker}"
MIN_TARGET_GB="${ROCKSTOR_HC4_MIN_FREE_TARGET_GB:-15}"
MIN_CACHE_GB="${ROCKSTOR_HC4_MIN_FREE_CACHE_GB:-10}"
MIN_VARTMP_GB="${ROCKSTOR_HC4_MIN_FREE_VARTMP_GB:-5}"
TARGET_DIR="${ROCKSTOR_KIWI_TARGET:-/mnt/bdata/kiwi-images-hc4}"
CACHE_DIR="${ROCKSTOR_KIWI_CACHE:-/mnt/bdata/cache}"
KIWI_VAR_TMP="${ROCKSTOR_KIWI_VAR_TMP:-/mnt/bdata/kiwi-var-tmp}"
IMAGE="${ROCKSTOR_WORKER_IMAGE:-rockstor-worker:arm64}"
UBOOT_SOURCE="${ROCKSTOR_UBOOT_SOURCE:-armbian}"
SKIP_UBOOT_FETCH="${ROCKSTOR_SKIP_UBOOT_FETCH:-0}"

failures=0
warnings=0

note_fail() {
	echo "validate-hc4-build-host: ERROR: $*" >&2
	failures=$((failures + 1))
}

note_warn() {
	echo "validate-hc4-build-host: WARNING: $*" >&2
	warnings=$((warnings + 1))
}

note_ok() {
	echo "validate-hc4-build-host: OK: $*"
}

avail_gb() {
	local path=$1
	local parent dir
	dir=$path
	while [[ ! -d "$dir" && "$dir" != "/" ]]; do
		dir=$(dirname "$dir")
	done
	if [[ ! -d "$dir" ]]; then
		echo ""
		return 1
	fi
	df -BG --output=avail "$dir" 2>/dev/null | awk 'NR==2 { gsub(/G/,"",$1); print $1 }'
}

check_min_free() {
	local label=$1 path=$2 min_gb=$3
	local avail
	avail=$(avail_gb "$path" || true)
	if [[ -z "${avail}" ]]; then
		note_fail "${label}: cannot determine free space for ${path} (mount missing?)"
		return
	fi
	if [[ "${avail}" -lt "${min_gb}" ]]; then
		note_fail "${label}: need at least ${min_gb} GB free at ${path} (have ${avail} GB)"
	else
		note_ok "${label}: ${avail} GB free at ${path} (need ${min_gb} GB)"
	fi
}

while [[ $# -gt 0 ]]; do
	case "$1" in
		--docker) MODE=docker ;;
		--native) MODE=native ;;
		-h|--help)
			echo "Usage: $0 [--docker|--native]" >&2
			exit 0
			;;
		*)
			echo "Unknown option: $1" >&2
			exit 2
			;;
	esac
	shift
done

if [[ "${ROCKSTOR_SKIP_HC4_VALIDATE:-0}" == 1 ]]; then
	echo "validate-hc4-build-host: skipped (ROCKSTOR_SKIP_HC4_VALIDATE=1)"
	exit 0
fi

echo "validate-hc4-build-host: Tumbleweed.OdroidHC4 pre-flight (mode=${MODE})"

arch=$(uname -m)
if [[ "${arch}" != "aarch64" ]]; then
	note_fail "host CPU is ${arch}; HC4 profile requires aarch64 (use arm64 hardware or a self-hosted worker)"
else
	note_ok "host architecture is aarch64"
fi

if [[ ! -f "${REPO_ROOT}/rockstor.kiwi" ]]; then
	note_fail "missing ${REPO_ROOT}/rockstor.kiwi (run from rockstor-installer checkout)"
else
	note_ok "rockstor.kiwi present"
fi

for f in root/boot/odroid-hc4.dtb root/boot/extlinux/extlinux.conf; do
	if [[ ! -f "${REPO_ROOT}/${f}" ]]; then
		note_fail "missing ${REPO_ROOT}/${f}"
	else
		note_ok "found ${f}"
	fi
done

check_min_free "KIWI target" "${TARGET_DIR}" "${MIN_TARGET_GB}"
check_min_free "zypper cache" "${CACHE_DIR}" "${MIN_CACHE_GB}"
if [[ "${MODE}" == docker ]]; then
	check_min_free "container TMPDIR" "${KIWI_VAR_TMP}" "${MIN_VARTMP_GB}"
fi

if [[ "${SKIP_UBOOT_FETCH}" != 1 ]]; then
	if [[ "${UBOOT_SOURCE}" == armbian ]]; then
		if ! command -v dpkg-deb >/dev/null 2>&1; then
			note_fail "dpkg-deb not found (install dpkg; required to extract Armbian linux-u-boot-odroidhc4-current .deb)"
		else
			note_ok "dpkg-deb available for U-Boot fetch"
		fi
	fi
	if ! command -v curl >/dev/null 2>&1; then
		note_fail "curl not found (required for scripts/fetch-uboot-odroid-hc4.sh)"
	else
		note_ok "curl available"
	fi
else
	if [[ ! -f "${REPO_ROOT}/root/boot/u-boot.bin" ]]; then
		note_fail "ROCKSTOR_SKIP_UBOOT_FETCH=1 but ${REPO_ROOT}/root/boot/u-boot.bin is missing"
	else
		note_ok "root/boot/u-boot.bin present (fetch skipped)"
	fi
fi

if [[ "${MODE}" == docker ]]; then
	if ! command -v docker >/dev/null 2>&1; then
		note_fail "docker not found"
	else
		note_ok "docker installed"
		if docker info >/dev/null 2>&1; then
			note_ok "docker daemon reachable"
		elif sudo docker info >/dev/null 2>&1; then
			note_ok "docker daemon reachable via sudo"
		else
			note_fail "cannot talk to docker daemon (try: sudo docker info)"
		fi
		if docker image inspect "${IMAGE}" >/dev/null 2>&1 || sudo docker image inspect "${IMAGE}" >/dev/null 2>&1; then
			note_ok "worker image ${IMAGE} exists"
		else
			note_fail "docker image ${IMAGE} not found (build: docker build -f .cursor/worker.Dockerfile -t ${IMAGE} .cursor)"
		fi
	fi
	if ! grep -q '^loop ' /proc/modules 2>/dev/null && ! sudo modprobe loop max_part=8 2>/dev/null; then
		note_warn "could not load loop module (may need root for kiwi loop devices)"
	else
		note_ok "loop module available (max_part=8 recommended)"
	fi
else
	if ! command -v kiwi-ng >/dev/null 2>&1; then
		note_fail "kiwi-ng not found (install python3-kiwi on openSUSE aarch64)"
	else
		note_ok "kiwi-ng on PATH"
	fi
	if [[ "$(id -u)" -ne 0 ]]; then
		if ! sudo -n true 2>/dev/null; then
			note_warn "native build usually needs sudo for loop devices; ensure sudo works"
		else
			note_ok "sudo available"
		fi
	fi
fi

if [[ "${failures}" -gt 0 ]]; then
	echo "validate-hc4-build-host: failed (${failures} error(s), ${warnings} warning(s))" >&2
	exit 1
fi

echo "validate-hc4-build-host: passed (${warnings} warning(s))"
exit 0
