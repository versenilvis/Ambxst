#!/usr/bin/env bash

# Kill notification daemons that may conflict
for daemon in dunst mako swaync; do
	if pgrep -x "$daemon" >/dev/null; then
		echo "Stopping $daemon..."
		pkill -x "$daemon"
	fi
done

# EasyEffects
if command -v easyeffects >/dev/null; then
	if ! pgrep -x easyeffects >/dev/null; then
		echo "Starting EasyEffects..."
		nohup easyeffects --gapplication-service >/dev/null 2>&1 &
	else
		echo "EasyEffects is already running"
	fi
fi

# Ambxst Daemon
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
REPO_ROOT=$(dirname "$SCRIPT_DIR")
DAEMON_BIN="$REPO_ROOT/bin/ambxst-daemon"
[ ! -f "$DAEMON_BIN" ] && DAEMON_BIN="$REPO_ROOT/ambxst-daemon/target/release/ambxst-daemon"

if [ -f "$DAEMON_BIN" ] && ! pgrep -x ambxst-daemon >/dev/null; then
	echo "Starting ambxst-daemon..."
	nohup "$DAEMON_BIN" >/dev/null 2>&1 &
fi

