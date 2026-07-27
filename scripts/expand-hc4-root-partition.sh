#!/usr/bin/env bash
# Host/repo wrapper for the image-installed expand helper (see root/usr/libexec/...).
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec bash "${REPO_ROOT}/root/usr/libexec/rockstor-hc4-expand-root-partition.sh" "$@"
