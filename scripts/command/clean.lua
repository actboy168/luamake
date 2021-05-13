local util = require "util"
local globals = require "globals"

util.command('init', true)

if globals.compiler == "msvc" then
    local msvc = require "msvc_util"
    if msvc.hasEnvConfig() then
        util.ninja { "-t", "clean" }
        msvc.cleanEnvConfig()
    else
        local fs = require "bee.filesystem"
        pcall(fs.remove_all, fs.path(globals.builddir))
    end
else
    util.ninja { "-t", "clean" }
end
