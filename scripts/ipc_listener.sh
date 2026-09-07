#!/usr/bin/env bash

pipe="/tmp/ambxst_ipc.pipe"
lock_file="${XDG_RUNTIME_DIR:-/tmp}/ambxst-ipc-listener.lock"
owner_pid="${1:-$PPID}"

mkdir -p "$(dirname "$lock_file")"
exec 9>"$lock_file"
flock -n 9 || exit 0

rm -f "$pipe"
mkfifo "$pipe"
chmod 600 "$pipe" 2>/dev/null || true

cleanup() {
	trap - EXIT INT TERM HUP
	kill $(jobs -p) 2>/dev/null || true
	exec 3>&- 2>/dev/null || true
	rm -f "$pipe"
	exit 0
}

trap cleanup EXIT INT TERM HUP

# keep pipe open for read/write so it never reaches eof on writer close
exec 3<>"$pipe"

if [ -n "$owner_pid" ] && [ "$owner_pid" -gt 1 ] 2>/dev/null; then
	(
		while kill -0 "$owner_pid" 2>/dev/null; do
			sleep 1
		done
		cleanup
	) &
fi

while read -r line <&3; do
	if [ -n "$line" ]; then
		echo "$line"
	fi
done
