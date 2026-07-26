#!/bin/sh
# HC4 blue status LED: load ledtrig-heartbeat and use kernel heartbeat trigger only.
set -eu

MODE=${1:---oneshot}

load_led_triggers() {
	type modprobe >/dev/null 2>&1 || return 0
	modprobe ledtrig-heartbeat 2>/dev/null || true
}

find_blue_led() {
	for _c in /sys/class/leds/blue /sys/class/leds/blue:* /sys/class/leds/led-blue*; do
		[ -e "$_c" ] || continue
		[ -f "$_c/trigger" ] || continue
		printf '%s' "$_c"
		return 0
	done
	return 1
}

apply_kernel_heartbeat() {
	_led=$1
	load_led_triggers
	grep -q '\[heartbeat\]' "$_led/trigger" 2>/dev/null || return 1
	echo heartbeat >"$_led/trigger" 2>/dev/null
}

oneshot_with_retry() {
	_i=1
	while [ "$_i" -le 15 ]; do
		_led=$(find_blue_led) || {
			sleep 1
			_i=$((_i + 1))
			continue
		}
		if apply_kernel_heartbeat "$_led"; then
			return 0
		fi
		sleep 1
		_i=$((_i + 1))
	done
	return 1
}

case "$MODE" in
	--oneshot)
		oneshot_with_retry || true
		;;
	--run)
		# Back-compat: same as oneshot (no userspace blink loop).
		oneshot_with_retry || true
		;;
	*)
		echo "Usage: $0 [--oneshot|--run]" >&2
		exit 2
		;;
esac
