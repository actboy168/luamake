local util = require "util"
local arguments = require "arguments"

if arguments.args.plat == "msvc" then
    local msvc = require "msvc_util"
    if msvc.hasEnvConfig() then
        util.ninja { "-t", "clean" }
        msvc.cleanEnvConfig()
    else
        local fs = require "bee.filesystem"
        pcall(fs.remove_all, WORKDIR / "build" / "msvc")
    end
else
    util.ninja { "-t", "clean" }
end
