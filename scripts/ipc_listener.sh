#!/usr/bin/env bash

PIPE="/tmp/ambxst_ipc.pipe"
LOCK_FILE="${XDG_RUNTIME_DIR:-/tmp}/ambxst-ipc-listener.lock"
OWNER_PID="${1:-$PPID}"

exec 9>"$LOCK_FILE"
flock -n 9 || exit 0

rm -f "$PIPE"
mkfifo "$PIPE"

cleanup() {
	rm -f "$PIPE"
}

trap cleanup EXIT INT TERM

tail --pid="$OWNER_PID" -f "$PIPE" &
tail_pid=$!

wait "$tail_pid"
