function fish_greeting
    # Two quiet lines: security status, then the session at a glance.
    # The status comes from Lumi (~/.local/state/lumi/privacy-status).
    set -l status_file (set -q XDG_STATE_HOME; and echo $XDG_STATE_HOME; or echo $HOME/.local/state)/lumi/privacy-status
    set -l privacy (string trim -- (cat $status_file 2>/dev/null))
    set -l kind (string split -m1 ' ' -- $privacy)[1]
    set -l detail (string split -m1 ' ' -- $privacy)[2]

    # Uptime from /proc, as "3h 21m"
    set -l secs (string split ' ' -- (cat /proc/uptime))[1]
    set secs (math -s0 $secs)
    set -l up (math -s0 $secs / 3600)h' '(math -s0 $secs % 3600 / 60)m
    test $secs -lt 3600; and set up (math -s0 $secs / 60)m

    # RAM in use
    set -l mem_total (string match -r '\d+' -- (grep MemTotal /proc/meminfo))
    set -l mem_avail (string match -r '\d+' -- (grep MemAvailable /proc/meminfo))
    set -l ram (math -s0 "($mem_total - $mem_avail) * 100 / $mem_total")

    echo
    set_color blue; echo -n '  ▍ '
    switch "$kind"
        case tor vpn
            set_color green; echo -n '󰒃 protected'
            set_color brblack; echo -n ' · '
            set_color normal; echo -n "$kind"
            test -n "$detail"; and begin
                set_color brblack; echo -n ' · '
                set_color normal; echo -n "$detail"
            end
        case offline
            set_color red; echo -n '󰖪 offline'
            set_color brblack; echo -n ' · network killed'
        case '*'
            set_color yellow; echo -n ' exposed'
            set_color brblack; echo -n ' · direct connection'
    end
    echo

    set_color blue; echo -n '  ▍ '
    set_color normal; echo -n (date "+%a %d %b")
    set_color brblack; echo -n ' · '
    set_color normal; echo -n (date "+%H:%M")
    set_color brblack; echo -n '   up '
    set_color normal; echo -n $up
    set_color brblack; echo -n '   ram '
    set_color normal; echo -n $ram%
    set_color normal
    echo
end
