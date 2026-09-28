#!/usr/bin/env bash
# Projector / external screen helper for Hyprland on laptops.
#   projector.sh plugged    - called on monitor.added: mirror the laptop screen, route audio, notify
#   projector.sh unplugged  - called on monitor.removed: route audio back to the laptop
#   projector.sh toggle     - switch the external screen between mirror and extend
#   projector.sh audio      - pick the right audio output for the current state
#
# Screens are detected from /sys/class/drm, so any connector names work. On a
# desktop (no built-in laptop panel) it does nothing and Hyprland's defaults apply.

# Connected connectors, as Hyprland names them (card1-HDMI-A-1 -> HDMI-A-1)
connected() {
    local status
    for status in /sys/class/drm/card*-*/status; do
        [[ $(<"$status") == connected ]] || continue
        status=${status%/status}
        echo "${status##*/card[0-9]-}"
    done
}

INT=$(connected | grep -m1 -E '^(eDP|LVDS|DSI)')
EXT=$(connected | grep -m1 -v -E '^(eDP|LVDS|DSI)')

notify() {
    notify-send -a Projector -i video-display "$1" "${2:-}"
}

audio() {
    local sink=""
    if [[ -n $EXT ]]; then
        # HDMI/DP sink ports only become "available" once the display's ELD is read, so retry briefly
        for _ in {1..10}; do
            sink=$(pactl list sinks | awk '/^\s*Name:/ { n = $2 } /\[Out\] (HDMI|DisplayPort).*, available\)/ { print n; exit }')
            [[ -n $sink ]] && break
            sleep 0.5
        done
    else
        sink=$(pactl list short sinks | awk '$2 !~ /hdmi|HDMI/ { print $2; exit }')
    fi
    [[ -n $sink ]] && pactl set-default-sink "$sink"
}

set_mode() {
    local mirror=""
    [[ $1 == mirror ]] && mirror=", mirror = \"$INT\""
    hyprctl eval "hl.monitor({ output = \"$EXT\", mode = \"preferred\", position = \"auto\", scale = 1$mirror })" >/dev/null
}

mirroring() {
    hyprctl monitors all -j | python3 -c "
import json, sys
print(next((m.get('mirrorOf', '') for m in json.load(sys.stdin) if m['name'] == sys.argv[1]), ''))
" "$EXT"
}

# Desktops (no laptop panel) are left alone
[[ -n $INT ]] || exit 0

case ${1:-} in
    plugged)
        # monitor.added also fires for the laptop screen at startup, so only act on an external one
        [[ -n $EXT ]] || exit 0
        set_mode mirror
        notify "Projector connected" "Mirroring screen · Super+Shift+P to extend"
        audio
        ;;
    unplugged)
        [[ -n $EXT ]] && exit 0
        audio
        ;;
    toggle)
        if [[ -z $EXT ]]; then
            notify "No external screen" "Plug in the HDMI cable first"
            exit 1
        fi
        if [[ $(mirroring) == "$INT" ]]; then
            set_mode extend
            notify "Projector: extended display" "Drag windows to the right onto the projector"
        else
            set_mode mirror
            notify "Projector: mirroring" "Projector shows the same as your laptop"
        fi
        ;;
    audio) audio ;;
    *)
        echo "usage: $0 {plugged|unplugged|toggle|audio}" >&2
        exit 1
        ;;
esac
