#!/usr/bin/env bash
# Download missing HC4 build inputs and build the Docker worker image when needed.
# Usage: scripts/prepare-hc4-build-host.sh [--docker|--native]
# Run before validate-hc4-build-host.sh (run-odroid-hc4-kiwi-build.sh does both).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${ROCKSTOR_HC4_BUILD_MODE:-docker}"
TARGET_DIR="${ROCKSTOR_KIWI_TARGET:-/mnt/bdata/kiwi-images-hc4}"
CACHE_DIR="${ROCKSTOR_KIWI_CACHE:-/mnt/bdata/cache}"
KIWI_VAR_TMP="${ROCKSTOR_KIWI_VAR_TMP:-/mnt/bdata/kiwi-var-tmp}"
IMAGE="${ROCKSTOR_WORKER_IMAGE:-rockstor-worker:arm64}"
WORKER_DOCKERFILE="${ROCKSTOR_WORKER_DOCKERFILE:-${REPO_ROOT}/.cursor/worker.Dockerfile}"
WORKER_CONTEXT="${ROCKSTOR_WORKER_CONTEXT:-${REPO_ROOT}/.cursor}"
UBOOT_SOURCE="${ROCKSTOR_UBOOT_SOURCE:-armbian}"
SKIP_UBOOT_FETCH="${ROCKSTOR_SKIP_UBOOT_FETCH:-0}"
AUTO_PREPARE="${ROCKSTOR_HC4_AUTO_PREPARE:-1}"
AUTO_BUILD_WORKER="${ROCKSTOR_HC4_AUTO_BUILD_WORKER:-1}"
AUTO_INSTALL_DEPS="${ROCKSTOR_HC4_AUTO_INSTALL_HOST_DEPS:-1}"
AUTO_BUILD_DTB="${ROCKSTOR_HC4_AUTO_BUILD_DTB:-1}"

run_root() {
	if [[ "$(id -u)" -eq 0 ]]; then
		"$@"
	else
		sudo "$@"
	fi
}

log() {
	echo "prepare-hc4-build-host: $*"
}

docker_usable() {
	command -v docker >/dev/null 2>&1 && { docker info >/dev/null 2>&1 || run_root docker info >/dev/null 2>&1; }
}

docker_cmd() {
	if docker info >/dev/null 2>&1; then
		docker "$@"
	else
		run_root docker "$@"
	fi
}

docker_image_exists() {
	docker_cmd image inspect "$1" >/dev/null 2>&1
}

install_cmd_if_missing() {
	local cmd=$1
	shift
	[[ "${AUTO_INSTALL_DEPS}" == 1 ]] || return 0
	command -v "${cmd}" >/dev/null 2>&1 && return 0
	local pkgs=("$@")
	if command -v zypper >/dev/null 2>&1; then
		log "installing ${pkgs[*]} (provides ${cmd}) via zypper"
		run_root zypper --non-interactive install -y "${pkgs[@]}" || true
	elif command -v apt-get >/dev/null 2>&1; then
		log "installing ${pkgs[*]} via apt"
		run_root apt-get update -qq || true
		run_root apt-get install -y "${pkgs[@]}" || true
	fi
}

while [[ $# -gt 0 ]]; do
	case "$1" in
		--docker) MODE=docker ;;
		--native) MODE=native ;;
		-h|--help)
			cat <<EOF
Usage: $0 [--docker|--native]

Ensures output directories exist, installs curl/dpkg when possible, fetches
root/boot/u-boot.bin, builds rockstor-worker:arm64 if missing (docker mode),
and rebuilds odroid-hc4.dtb when missing.

ROCKSTOR_HC4_AUTO_PREPARE=0           skip this script entirely
ROCKSTOR_HC4_AUTO_BUILD_WORKER=0      do not docker build the worker image
ROCKSTOR_HC4_AUTO_INSTALL_HOST_DEPS=0 do not zypper/apt install curl/dpkg
ROCKSTOR_HC4_AUTO_BUILD_DTB=0         do not run build-hc4-linux-dtb.sh
EOF
			exit 0
			;;
		*)
			echo "Unknown option: $1" >&2
			exit 2
			;;
	esac
	shift
done

if [[ "${AUTO_PREPARE}" != 1 ]]; then
	log "skipped (ROCKSTOR_HC4_AUTO_PREPARE=${AUTO_PREPARE})"
	exit 0
fi

log "preparing Tumbleweed.OdroidHC4 build (mode=${MODE})"

run_root mkdir -p "${TARGET_DIR}" "${CACHE_DIR}" "${TARGET_DIR}/tmp" "${KIWI_VAR_TMP}"

if [[ "${SKIP_UBOOT_FETCH}" != 1 ]]; then
	if [[ "${UBOOT_SOURCE}" == armbian ]]; then
		install_cmd_if_missing dpkg-deb dpkg
	fi
	install_cmd_if_missing curl curl
fi

if [[ "${SKIP_UBOOT_FETCH}" != 1 && ! -f "${REPO_ROOT}/root/boot/u-boot.bin" ]]; then
	log "fetching root/boot/u-boot.bin (scripts/fetch-uboot-odroid-hc4.sh)"
	bash "${REPO_ROOT}/scripts/fetch-uboot-odroid-hc4.sh"
elif [[ -f "${REPO_ROOT}/root/boot/u-boot.bin" ]]; then
	log "root/boot/u-boot.bin already present"
fi

if [[ "${AUTO_BUILD_DTB}" == 1 && ! -f "${REPO_ROOT}/root/boot/odroid-hc4.dtb" ]]; then
	if [[ -x "${REPO_ROOT}/scripts/build-hc4-linux-dtb.sh" ]]; then
		install_cmd_if_missing fdtput device-tree-compiler
		if command -v fdtput >/dev/null 2>&1; then
			log "building missing root/boot/odroid-hc4.dtb"
			bash "${REPO_ROOT}/scripts/build-hc4-linux-dtb.sh"
		else
			log "WARNING: odroid-hc4.dtb missing and fdtput not available (install device-tree-compiler)"
		fi
	fi
fi

if [[ "${MODE}" == docker ]]; then
	if ! command -v docker >/dev/null 2>&1; then
		log "WARNING: docker not installed; cannot build worker image"
	elif ! docker_usable; then
		log "WARNING: docker daemon not reachable; start docker before build"
	elif ! docker_image_exists "${IMAGE}"; then
		if [[ "${AUTO_BUILD_WORKER}" != 1 ]]; then
			log "worker image ${IMAGE} missing (set ROCKSTOR_HC4_AUTO_BUILD_WORKER=1 to build)"
		elif [[ ! -f "${WORKER_DOCKERFILE}" ]]; then
			log "ERROR: missing ${WORKER_DOCKERFILE}" >&2
			exit 1
		else
			log "building worker image ${IMAGE} (this may take a while) ..."
			docker_cmd build -f "${WORKER_DOCKERFILE}" -t "${IMAGE}" "${WORKER_CONTEXT}"
			log "worker image ${IMAGE} built"
		fi
	else
		log "worker image ${IMAGE} already present"
	fi
fi

if [[ "${MODE}" == native ]]; then
	if ! command -v kiwi-ng >/dev/null 2>&1 && [[ "${AUTO_INSTALL_DEPS}" == 1 ]]; then
		if command -v zypper >/dev/null 2>&1; then
			log "kiwi-ng not found; installing python3-kiwi via zypper (native build)"
			run_root zypper --non-interactive install -y python3-kiwi || true
		fi
	fi
fi

log "prepare complete"
