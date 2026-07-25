#!/usr/bin/env bash
# Fetch pre-built openSUSE u-boot-odroid-c4 (see fetch-uboot-odroid-hc4.sh).
exec "$(cd "$(dirname "$0")" && pwd)/fetch-uboot-odroid-hc4.sh" "$@"
