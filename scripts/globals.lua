local arguments = require "arguments"

local globals = {}

for k, v in pairs(arguments.args) do
    globals[k] = v
end

if globals.plat then
    local sp = require 'bee.subprocess'
    sp.setenv("LuaMakePlatform", globals.plat)
else
    globals.plat = (function ()
        if os.getenv "LuaMakePlatform" then
            return os.getenv "LuaMakePlatform"
        end
        return require "plat"
    end)()
end

assert(globals.plat == "msvc"
    or globals.plat == "mingw"
    or globals.plat == "linux"
    or globals.plat == "macos"
)

do
    if globals.plat == "msvc" or globals.plat == "mingw" then
        if not globals.target then
            globals.target = string.packsize "T" == 8 and "x64" or "x86"
        end
        assert(globals.target == "x64" or globals.target == "x86")
    end
end
globals.mode = globals.mode or "release"
globals.crt = globals.crt or "dynamic"

return globals
