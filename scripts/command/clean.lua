local action = require "action"
local globals = require "globals"

action.init()

if globals.compiler == "msvc" then
    local msvc = require "msvc_util"
    if msvc.hasEnvConfig() then
        action.clean()
        msvc.cleanEnvConfig()
    else
        local fs = require "bee.filesystem"
        pcall(fs.remove_all, WORKDIR / globals.builddir)
    end
else
    action.clean()
end
