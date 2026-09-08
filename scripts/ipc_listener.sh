#!/usr/bin/env bash

pipe="/tmp/ambxst_ipc.pipe"
pid_file="${XDG_RUNTIME_DIR:-/tmp}/ambxst-ipc-listener.pid"
owner_pid="${1:-$PPID}"

mkdir -p "$(dirname "$pid_file")"

# terminate stale listener so active instance owns the pipe
if [ -f "$pid_file" ]; then
	old_pid=$(cat "$pid_file" 2>/dev/null || true)
	if [ -n "$old_pid" ] && [ "$old_pid" -ne "$$" ] 2>/dev/null && kill -0 "$old_pid" 2>/dev/null; then
		kill -TERM "$old_pid" 2>/dev/null || true
		for _ in 1 2 3 4 5; do
			kill -0 "$old_pid" 2>/dev/null || break
			sleep 0.02
		done
		kill -KILL "$old_pid" 2>/dev/null || true
	fi
fi

echo "$$" >"$pid_file"

rm -f "$pipe"
mkfifo "$pipe"
chmod 600 "$pipe" 2>/dev/null || true

cleanup() {
	trap - EXIT INT TERM HUP PIPE
	kill $(jobs -p) 2>/dev/null || true
	exec 3>&- 2>/dev/null || true
	rm -f "$pipe" "$pid_file"
	exit 0
}

trap cleanup EXIT INT TERM HUP PIPE

# keep pipe open for read/write so it never reaches eof on writer close
exec 3<>"$pipe"

main_pid=$$
if [ -n "$owner_pid" ] && [ "$owner_pid" -gt 1 ] 2>/dev/null; then
	(
		while kill -0 "$owner_pid" 2>/dev/null; do
			sleep 1
		done
		kill -TERM "$main_pid" 2>/dev/null || true
	) &
fi

while read -r line <&3; do
	if [ -n "$line" ]; then
		echo "$line"
	fi
done
