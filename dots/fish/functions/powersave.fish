function powersave
    sudo sh -c 'for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do echo powersave > "$f"; done'
end
