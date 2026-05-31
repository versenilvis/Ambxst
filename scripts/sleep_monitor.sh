#!/usr/bin/env bash

# sleep monitor that executes commands before and after sleep
CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/Ambxst/config/system.json"
LOCK_FILE="${XDG_RUNTIME_DIR:-/tmp}/ambxst-sleep-monitor.lock"
OWNER_PID="${1:-$PPID}"

exec 9>"$LOCK_FILE"
flock -n 9 || exit 0

get_cmd() {
    local type=$1
    if [ -f "$CONFIG_FILE" ]; then
        if [ "$type" == "before" ]; then
            jq -r '.idle.general.before_sleep_cmd // "loginctl lock-session"' "$CONFIG_FILE"
        else
            jq -r '.idle.general.after_sleep_cmd // "ambxst screen on"' "$CONFIG_FILE"
        fi
    else
        if [ "$type" == "before" ]; then
            echo "loginctl lock-session"
        else
            echo "ambxst screen on"
        fi
    fi
}

run_cmd() {
    local cmd=$1
    if [ -n "$cmd" ] && [ "$cmd" != "null" ]; then
        bash -lc "$cmd" 9>&- &
    fi
}

is_dpms_on_cmd() {
    local cmd=$1
    [ "$cmd" = "ambxst screen on" ] || [ "$cmd" = "hyprctl dispatch dpms on" ]
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
    # monitor logind's sleep signal
    dbus-monitor --system "type='signal',interface='org.freedesktop.login1.Manager',member='PrepareForSleep'" 9>&- | \
    while read -r line; do
        # look for the member line to confirm signal
        if echo "$line" | grep -q "member=PrepareForSleep"; then
            # read the next line which contains the boolean argument
            read -r arg_line
            if echo "$arg_line" | grep -q "true"; then
                # going to sleep
                CMD=$(get_cmd "before")
                run_cmd "$CMD"
            elif echo "$arg_line" | grep -q "false"; then
                CMD=$(get_cmd "after")
                # let hyprland and drm settle before touching dpms/brightness again
                if ! is_dpms_on_cmd "$CMD"; then
                    (sleep 3 && run_cmd "$CMD") 9>&- &
                fi
                (sleep 5 && ambxst brightness -r) 9>&- &
                if command -v nmcli >/dev/null 2>&1; then
                    (sleep 8 && nmcli radio wifi off && sleep 1 && nmcli radio wifi on) 9>&- &
                fi
            fi
        fi
    done
}
monitor_loop 9>&- &
monitor_pid=$!

wait "$monitor_pid"
