#!/usr/bin/env bash

OWNER_PID="${1:-$PPID}"

command -v nmcli >/dev/null 2>&1 || exit 0

nmcli monitor &
monitor_pid=$!

cleanup() {
	kill "$monitor_pid" 2>/dev/null || true
}

trap cleanup EXIT INT TERM

while kill -0 "$OWNER_PID" 2>/dev/null && kill -0 "$monitor_pid" 2>/dev/null; do
	sleep 1
done

cleanup
wait "$monitor_pid" 2>/dev/null || true
