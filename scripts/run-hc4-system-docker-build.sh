#!/usr/bin/env bash
# Tumbleweed.OdroidHC4 kiwi build via privileged *system* Docker (not rootless).
#
# Rootless Docker cannot run kiwi-ng system build (proc mount in chroot fails).
# On a self-hosted worker without passwordless sudo, run this once with your password:
#
#   cd rockstor-installer && git checkout odroid-hc4
#   export ROCKSTOR_KIWI_TARGET="$HOME/kiwi-images-hc4"
#   export ROCKSTOR_KIWI_CACHE="$HOME/kiwi-cache"
#   export ROCKSTOR_KIWI_VAR_TMP="$HOME/kiwi-var-tmp"
#   sudo -E bash scripts/run-hc4-system-docker-build.sh
#
# Optional: ROCKSTOR_BUILD_USER=seb (default: SUDO_USER), ROCKSTOR_SKIP_WORKER_BUILD=1
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
	exec sudo -E "$0" "$@"
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_USER="${ROCKSTOR_BUILD_USER:-${SUDO_USER:-root}}"
if [[ "${BUILD_USER}" == root || -z "${BUILD_USER}" ]]; then
	echo "Set ROCKSTOR_BUILD_USER or run via sudo as a normal user (SUDO_USER)." >&2
	exit 1
fi
BUILD_HOME="$(getent passwd "${BUILD_USER}" | cut -d: -f6)"
IMAGE="${ROCKSTOR_WORKER_IMAGE:-rockstor-worker:arm64}"
CONTAINER_NAME="${ROCKSTOR_KIWI_CONTAINER:-rockstor-odroid-hc4-build}"
TARGET_DIR="${ROCKSTOR_KIWI_TARGET:-${BUILD_HOME}/kiwi-images-hc4}"
CACHE_DIR="${ROCKSTOR_KIWI_CACHE:-${BUILD_HOME}/kiwi-cache}"
KIWI_VAR_TMP="${ROCKSTOR_KIWI_VAR_TMP:-${BUILD_HOME}/kiwi-var-tmp}"
LOG="${ROCKSTOR_KIWI_LOG:-${BUILD_HOME}/kiwi-build-odroid-hc4.log}"
PROFILE="${ROCKSTOR_KIWI_PROFILE:-Tumbleweed.OdroidHC4}"
KIWI_PREP_PKGS="util-linux util-linux-systemd pam_pwquality device-mapper kpartx parted systemd"

unset DOCKER_HOST
export DOCKER_HOST="${ROCKSTOR_DOCKER_HOST:-unix:///run/docker.sock}"

systemctl enable --now docker
if ! getent group docker | grep -qF "${BUILD_USER}"; then
	usermod -aG docker "${BUILD_USER}" || true
	echo "Added ${BUILD_USER} to group docker (log out/in if docker permission errors persist)."
fi

modprobe loop max_part=8 2>/dev/null || true
sysctl -w fs.protected_symlinks=0 fs.protected_hardlinks=0 2>/dev/null || true
mkdir -p "${TARGET_DIR}" "${CACHE_DIR}" "${TARGET_DIR}/tmp" "${KIWI_VAR_TMP}"
chown -R "${BUILD_USER}:${BUILD_USER}" "${TARGET_DIR}" "${CACHE_DIR}" "${KIWI_VAR_TMP}" 2>/dev/null || true

export ROCKSTOR_KIWI_TARGET="${TARGET_DIR}" ROCKSTOR_KIWI_CACHE="${CACHE_DIR}" ROCKSTOR_KIWI_VAR_TMP="${KIWI_VAR_TMP}"
export ROCKSTOR_WORKER_IMAGE="${IMAGE}"
export ROCKSTOR_UBOOT_SOURCE="${ROCKSTOR_UBOOT_SOURCE:-armbian}"
if [[ "${ROCKSTOR_UBOOT_SOURCE}" != armbian ]]; then
	echo "WARNING: ROCKSTOR_UBOOT_SOURCE=${ROCKSTOR_UBOOT_SOURCE} (HC4 images expect Armbian U-Boot; see README)" >&2
fi

# Armbian .deb extract runs on the host before the container (needs dpkg-deb).
if [[ "${ROCKSTOR_SKIP_UBOOT_FETCH:-0}" != 1 && "${ROCKSTOR_UBOOT_SOURCE}" == armbian ]]; then
	if command -v zypper >/dev/null 2>&1; then
		zypper --non-interactive install -y dpkg curl || true
	elif command -v apt-get >/dev/null 2>&1; then
		apt-get update -qq || true
		apt-get install -y dpkg curl || true
	fi
fi

sudo -u "${BUILD_USER}" -E bash "${REPO_ROOT}/scripts/prepare-hc4-build-host.sh" --docker
sudo -u "${BUILD_USER}" -E bash "${REPO_ROOT}/scripts/validate-hc4-build-host.sh" --docker

if [[ "${ROCKSTOR_SKIP_WORKER_BUILD:-0}" != 1 ]] && ! docker image inspect "${IMAGE}" >/dev/null 2>&1; then
	docker build -f "${REPO_ROOT}/.cursor/worker.Dockerfile" -t "${IMAGE}" "${REPO_ROOT}/.cursor"
fi

if [[ ! -f "${REPO_ROOT}/root/boot/u-boot.bin" ]]; then
	echo "Missing ${REPO_ROOT}/root/boot/u-boot.bin" >&2
	exit 1
fi
if [[ "${ROCKSTOR_SKIP_UBOOT_FETCH:-0}" != 1 && "${ROCKSTOR_UBOOT_SOURCE}" == armbian ]]; then
	uboot_style="${REPO_ROOT}/root/boot/.uboot-install-style"
	if [[ ! -f "${uboot_style}" ]] || [[ "$(tr -d '[:space:]' <"${uboot_style}")" != armbian ]]; then
		echo "Refusing to build: ${REPO_ROOT}/root/boot/u-boot.bin must be from latest Armbian package." >&2
		echo "Run: ROCKSTOR_UBOOT_SOURCE=armbian bash ${REPO_ROOT}/scripts/fetch-uboot-odroid-hc4.sh" >&2
		exit 1
	fi
fi

docker rm -f "${CONTAINER_NAME}" 2>/dev/null || true
rm -rf "${TARGET_DIR}/build" "${TARGET_DIR}"/*.raw "${TARGET_DIR}"/*.changes \
	"${TARGET_DIR}"/*.packages "${TARGET_DIR}"/*.verified \
	"${TARGET_DIR}"/kiwi.result "${TARGET_DIR}"/kiwi.result.json 2>/dev/null || true

echo "=== BUILD $(date -Iseconds) profile=${PROFILE} target=${TARGET_DIR} (system docker) ===" | tee -a "${LOG}"
docker run -d --name "${CONTAINER_NAME}" --privileged --cap-add SYS_ADMIN \
	--security-opt seccomp=unconfined \
	--pid=host \
	-v /dev:/dev \
	-v "${REPO_ROOT}:/workspace" \
	-v "${TARGET_DIR}:/home/kiwi-images" \
	-v "${CACHE_DIR}:/kiwi-package-cache" \
	-v "${KIWI_VAR_TMP}:/var/tmp" \
	-e TMPDIR=/var/tmp \
	-w /workspace \
	"${IMAGE}" \
	bash /workspace/scripts/hc4-kiwi-build-inner.sh build

chown "${BUILD_USER}:${BUILD_USER}" "${LOG}" 2>/dev/null || true
echo "Started ${CONTAINER_NAME} profile=${PROFILE}. Monitor: docker logs -f ${CONTAINER_NAME}"
echo "Output: ${TARGET_DIR}/Rockstor-NAS.aarch64-*.raw"
