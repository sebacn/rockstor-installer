#!/bin/sh
# Set HC4 status LED (blue) to kernel heartbeat trigger when sysfs node exists.
set -eu

set_hc4_blue_led_heartbeat() {
	_led=""
	for _c in /sys/class/leds/blue /sys/class/leds/blue:* /sys/class/leds/led-blue*; do
		[ -e "$_c" ] || continue
		[ -f "$_c/trigger" ] || continue
		_led=$_c
		break
	done
	[ -n "$_led" ] || return 0
	grep -q '\[heartbeat\]' "$_led/trigger" 2>/dev/null || return 0
	echo heartbeat >"$_led/trigger" 2>/dev/null || true
}

set_hc4_blue_led_heartbeat
