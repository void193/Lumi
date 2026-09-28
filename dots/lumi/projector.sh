#!/usr/bin/env bash
# Projector / external HDMI helper for Hyprland.
#   projector.sh plugged    - called on monitor.added: route audio to HDMI, notify
#   projector.sh unplugged  - called on monitor.removed: route audio back to laptop
#   projector.sh toggle     - switch HDMI between mirror and extend
#   projector.sh audio      - pick the right audio output for the current state

EXT=HDMI-A-1
INT=eDP-1

hdmi_connected() {
    grep -qx connected /sys/class/drm/card*-"$EXT"/status 2>/dev/null
}

notify() {
    notify-send -a Projector -i video-display "$1" "${2:-}"
}

audio() {
    if hdmi_connected; then
        # HDMI sink ports only become "available" once the display's ELD is read, so retry briefly
        for _ in {1..10}; do
            sink=$(pactl list sinks | awk '/^\s*Name:/ { n = $2 } /\[Out\] HDMI.*, available\)/ { print n; exit }')
            [[ -n $sink ]] && break
            sleep 0.5
        done
    else
        sink=$(pactl list short sinks | awk '$2 !~ /HDMI/ { print $2; exit }')
    fi

    [[ -n ${sink:-} ]] && pactl set-default-sink "$sink"
}

set_mode() {
    local mirror=""
    [[ $1 == mirror ]] && mirror=", mirror = \"$INT\""
    hyprctl eval "hl.monitor({ output = \"$EXT\", mode = \"preferred\", position = \"auto\", scale = 1$mirror })" >/dev/null
}

case ${1:-} in
    plugged)
        # monitor.added also fires for the laptop screen at startup, so only act on HDMI
        hdmi_connected || exit 0
        notify "Projector connected" "Mirroring screen · Super+Shift+P to extend"
        audio
        ;;
    unplugged)
        hdmi_connected && exit 0
        audio
        ;;
    toggle)
        if ! hdmi_connected; then
            notify "No projector connected" "Plug in the HDMI cable first"
            exit 1
        fi
        if [[ $(hyprctl monitors all -j | jq -r ".[] | select(.name == \"$EXT\") | .mirrorOf") == "$INT" ]]; then
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
