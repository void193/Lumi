-- Projector / external HDMI: mirror the laptop screen as soon as the cable is plugged in
hl.monitor({
    output   = "HDMI-A-1",
    mode     = "preferred",
    position = "auto",
    scale    = 1,
    mirror   = "eDP-1",
})

local projector = os.getenv("HOME") .. "/.config/lumi/projector.sh"
hl.on("monitor.added", function() hl.exec_cmd(projector .. " plugged") end)
hl.on("monitor.removed", function() hl.exec_cmd(projector .. " unplugged") end)
hl.bind("SUPER + SHIFT + P", hl.dsp.exec_cmd(projector .. " toggle")) -- mirror <-> extend
