#!/usr/bin/env bash
# Runs inside rockstor-worker container before kiwi-ng (HC4 MBR / disk_start_sector=8192).
set -euo pipefail

KIWI_PREP_PKGS="${KIWI_PREP_PKGS:-util-linux util-linux-systemd pam_pwquality device-mapper kpartx parted systemd}"
PROFILE="${ROCKSTOR_KIWI_PROFILE:-Tumbleweed.OdroidHC4}"
TARGET_DIR="${KIWI_TARGET_DIR:-/home/kiwi-images}"
CACHE_DIR="${KIWI_CACHE_DIR:-/kiwi-package-cache}"

run_root() {
	if [[ "$(id -u)" -eq 0 ]]; then
		"$@"
	else
		sudo "$@"
	fi
}

patch_kiwi_msdos() {
	local f patched=0
	for f in /usr/lib/python3*/site-packages/kiwi/partitioner/msdos.py; do
		[[ -f "$f" ]] || continue
		if grep -q 'mbsize += int(' "$f"; then
			run_root sed -i 's/mbsize += int(/mbsize = int(mbsize) + int(/' "$f"
			echo "hc4-kiwi-build-inner: patched $f"
			patched=1
		fi
	done
	if [[ "$patched" -eq 0 ]]; then
		if ! grep -rq 'mbsize = int(mbsize) + int(' /usr/lib/python3*/site-packages/kiwi/partitioner/msdos.py 2>/dev/null; then
			echo "hc4-kiwi-build-inner: ERROR: could not patch kiwi/partitioner/msdos.py" >&2
			return 1
		fi
		echo "hc4-kiwi-build-inner: kiwi msdos patch already present"
	fi
	return 0
}

verify_kiwi_msdos_patch() {
	local f
	for f in /usr/lib/python3*/site-packages/kiwi/partitioner/msdos.py; do
		[[ -f "$f" ]] || continue
		if grep -q 'mbsize += int(' "$f"; then
			echo "hc4-kiwi-build-inner: ERROR: unpatched kiwi still has mbsize += int( in $f" >&2
			return 1
		fi
	done
	echo "hc4-kiwi-build-inner: verified kiwi msdos mbsize patch"
}

case "${1:-build}" in
	patch-only)
		patch_kiwi_msdos
		verify_kiwi_msdos_patch
		exit 0
		;;
	build)
		run_root zypper --non-interactive in -y ${KIWI_PREP_PKGS}
		command -v lsblk >/dev/null
		run_root modprobe loop max_part=8 2>/dev/null || true
		run_root sysctl -w fs.protected_symlinks=0 fs.protected_hardlinks=0 >/dev/null 2>&1 || true
		if [[ -x /workspace/scripts/patch-kiwi-msdos-mbsize.sh ]]; then
			run_root bash /workspace/scripts/patch-kiwi-msdos-mbsize.sh
		fi
		patch_kiwi_msdos
		verify_kiwi_msdos_patch
		exec run_root kiwi-ng --shared-cache-dir="${CACHE_DIR}" --profile="${PROFILE}" --type oem system build \
			--description /workspace --target-dir "${TARGET_DIR}"
		;;
	*)
		echo "Usage: $0 [build|patch-only]" >&2
		exit 2
		;;
esac
