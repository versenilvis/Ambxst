#!/usr/bin/env bash

CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/Ambxst/config/system.json"
LOCK_FILE="${XDG_RUNTIME_DIR:-/tmp}/ambxst-loginlock.lock"
OWNER_PID="${1:-$PPID}"

exec 9>"$LOCK_FILE"
flock -n 9 || exit 0

get_lock_cmd() {
	if [ -f "$CONFIG_FILE" ]; then
		jq -r '.idle.general.lock_cmd // "ambxst lock"' "$CONFIG_FILE"
	else
		echo "ambxst lock"
	fi
}

cleanup() {
	trap - EXIT INT TERM
	pkill -P $$ 2>/dev/null || true
	exit 0
}
trap cleanup EXIT INT TERM

# watchdog to monitor parent pid
watchdog() {
	while kill -0 "$OWNER_PID" 2>/dev/null; do
		sleep 2
	done
	kill "$$" 2>/dev/null
}
watchdog 9>&- &

# main loop in background
monitor_loop() {
	dbus-monitor --system "type='signal',interface='org.freedesktop.login1.Session',member='Lock'" 9>&- |
		while read -r line; do
			if echo "$line" | grep -q "member=Lock"; then
				COMMAND=$(get_lock_cmd)
				if [ -n "$COMMAND" ] && [ "$COMMAND" != "null" ]; then
					bash -lc "$COMMAND" 9>&- &
				fi
			fi
		done
}
monitor_loop 9>&- &
monitor_pid=$!

wait "$monitor_pid"
