local action = require "action"
local globals = require "globals"

action.init()

if globals.compiler == "msvc" then
    local msvc = require "env.msvc"
    if msvc.hasEnvConfig() then
        action.clean()
        msvc.cleanEnvConfig()
    else
        local fs = require "bee.filesystem"
        local fsutil = require "fsutil"
        local builddir = fsutil.join(WORKDIR, globals.builddir)
        pcall(fs.remove_all, builddir)
    end
else
    action.clean()
end
