#!/usr/bin/env bash

# Check if any visible Firefox window exists in Hyprland
if ! hyprctl clients | grep -q "class: [Ff]irefox"; then
    # No visible window exists, but a process is lingering in the background
    if pgrep -x "firefox" > /dev/null; then
        killall -9 firefox
        # Give kernel a fraction of a second to release the profile lock
        sleep 0.1
    fi
fi

exec firefox "$@"