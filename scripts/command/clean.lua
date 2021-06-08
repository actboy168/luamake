local util = require "util"
local globals = require "globals"

util.cmd_init(true)

if globals.compiler == "msvc" then
    local msvc = require "msvc_util"
    if msvc.hasEnvConfig() then
        util.cmd_clean()
        msvc.cleanEnvConfig()
    else
        local fs = require "bee.filesystem"
        pcall(fs.remove_all, fs.path(globals.builddir))
    end
else
    util.cmd_clean()
end
