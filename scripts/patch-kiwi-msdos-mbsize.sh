#!/usr/bin/env bash
# Kiwi bug: disk_start_sector > 2048 + bootpartition uses str mbsize in msdos.py
# (TypeError: can only concatenate str (not "int") to str). See Tumbleweed.OdroidHC4.
set -euo pipefail
patched=0
for f in /usr/lib/python3*/site-packages/kiwi/partitioner/msdos.py; do
	[[ -f "$f" ]] || continue
	if grep -q 'mbsize += int(' "$f"; then
		sed -i 's/mbsize += int(/mbsize = int(mbsize) + int(/' "$f"
		echo "patch-kiwi-msdos-mbsize: updated $f"
		patched=1
	fi
done
if [[ "$patched" -eq 0 ]]; then
	if grep -rq 'mbsize = int(mbsize) + int(' /usr/lib/python3*/site-packages/kiwi/partitioner/msdos.py 2>/dev/null; then
		echo "patch-kiwi-msdos-mbsize: already applied"
	else
		echo "patch-kiwi-msdos-mbsize: WARNING: kiwi/partitioner/msdos.py not found" >&2
		exit 1
	fi
fi
