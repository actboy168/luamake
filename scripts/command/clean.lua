local util = require "util"

util.ninja { "-t", "clean" }

local arguments = require "arguments"
if arguments.plat == "msvc" then
    local msvc = require "msvc_util"
    msvc.cleanEnvConfig()
end
