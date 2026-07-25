#!/usr/bin/env bash
# Fetch pre-built ODROID-HC4 U-Boot (see fetch-uboot-odroid-hc4.sh).
exec "$(cd "$(dirname "$0")" && pwd)/fetch-uboot-odroid-hc4.sh" "$@"
