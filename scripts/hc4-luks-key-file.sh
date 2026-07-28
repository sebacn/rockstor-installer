#!/usr/bin/env bash
# Resolve LUKS passphrase file for HC4 image build / post-build extlinux validation.
set -euo pipefail

if [[ -n "${ROCKSTOR_HC4_LUKS_KEY_FILE:-}" && -f "${ROCKSTOR_HC4_LUKS_KEY_FILE}" ]]; then
	printf '%s\n' "${ROCKSTOR_HC4_LUKS_KEY_FILE}"
	exit 0
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
for candidate in "${repo_root}/.hc4-luks-passphrase" "/workspace/.hc4-luks-passphrase"; do
	if [[ -f "$candidate" ]]; then
		printf '%s\n' "$candidate"
		exit 0
	fi
done

echo "hc4-luks-key-file: create ${repo_root}/.hc4-luks-passphrase (chmod 600) or set ROCKSTOR_HC4_LUKS_KEY_FILE" >&2
exit 1
