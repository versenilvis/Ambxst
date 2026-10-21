#!/usr/bin/env bash
set -e

target="$1"
[ -z "$target" ] && exit 0

# decode file:// url if provided
if [[ "$target" == file://* ]]; then
    target="${target#file://}"
fi

# url decode if needed
target=$(python3 -c "import urllib.parse, sys; print(urllib.parse.unquote(sys.argv[1]))" "$target" 2>/dev/null || echo "$target")

# if target is a directory, open directly in file manager
if [ -d "$target" ]; then
    if command -v strata >/dev/null 2>&1; then
        nohup strata "$target" >/dev/null 2>&1 &
    elif command -v gio >/dev/null 2>&1; then
        nohup gio open "$target" >/dev/null 2>&1 &
    else
        nohup xdg-open "$target" >/dev/null 2>&1 &
    fi
    exit 0
fi

# if target is a .desktop application file
if [[ "$target" == *.desktop ]]; then
    if command -v gio >/dev/null 2>&1; then
        nohup gio launch "$target" >/dev/null 2>&1 &
    elif command -v gtk-launch >/dev/null 2>&1; then
        nohup gtk-launch "$(basename "$target")" >/dev/null 2>&1 &
    else
        nohup xdg-open "$target" >/dev/null 2>&1 &
    fi
    exit 0
fi

# query mime type and default application
mime=$(xdg-mime query filetype "$target" 2>/dev/null || true)
app=""
if [ -n "$mime" ]; then
    app=$(xdg-mime query default "$mime" 2>/dev/null || true)
fi

app_file=""
if [ -n "$app" ]; then
    app_file=$(find /usr/share/applications ~/.local/share/applications /var/lib/flatpak/exports/share/applications -name "$app" 2>/dev/null | head -n 1)
fi

# if handler application requires terminal (like neovim), spawn inside user terminal
if [ -n "$app_file" ] && grep -qi '^Terminal=true' "$app_file"; then
    exec_cmd=$(grep -i '^Exec=' "$app_file" | head -n 1 | sed 's/^Exec=//' | sed 's/%[fFuUdDnNickvm]//g')
    terminal="ghostty"
    if ! command -v "$terminal" >/dev/null 2>&1; then
        terminal="kitty"
    fi
    if command -v "$terminal" >/dev/null 2>&1; then
        nohup "$terminal" -e sh -c "$exec_cmd \"\$@\"" -- "$target" >/dev/null 2>&1 &
        exit 0
    fi
fi

# default open via gio open or xdg-open detached
if command -v gio >/dev/null 2>&1; then
    nohup gio open "$target" >/dev/null 2>&1 &
else
    nohup xdg-open "$target" >/dev/null 2>&1 &
fi
