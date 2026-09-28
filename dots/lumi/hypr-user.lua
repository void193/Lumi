-- Projector / external screen on laptops: mirror the laptop screen when a cable is plugged in.
-- projector.sh finds the screens itself and does nothing on desktops.
local projector = os.getenv("HOME") .. "/.config/lumi/projector.sh"
hl.on("monitor.added", function() hl.exec_cmd(projector .. " plugged") end)
hl.on("monitor.removed", function() hl.exec_cmd(projector .. " unplugged") end)
hl.bind("SUPER + SHIFT + P", hl.dsp.exec_cmd(projector .. " toggle")) -- mirror <-> extend
