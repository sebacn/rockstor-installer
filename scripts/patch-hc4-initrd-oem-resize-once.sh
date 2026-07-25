#!/usr/bin/env bash
# Back-compat wrapper; see patch-hc4-initrd.sh
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec "${REPO_ROOT}/scripts/patch-hc4-initrd.sh" "$@"
