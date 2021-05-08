local t = {}
local arguments = {}
local targets = {}
local what = arg[1]

local function has_command(what)
    local path = package.searchpath(what, (MAKEDIR / "scripts" / "command" / "?.lua"):string())
    return path ~= nil
end

if what == nil then
    what = 'remake'
else
    local i = 2
    if not has_command(what) then
        what = 'remake'
        i = 1
    end
    while i <= #arg do
        if arg[i]:sub(1, 1) == '-' then
            local k = arg[i]:sub(2)
            i = i + 1
            arguments[k] = arg[i]
        else
            targets[#targets+1] = arg[i]
        end
        i = i + 1
    end
end

t.what = what
t.targets = targets
t.C = arguments.C               ; arguments.C = nil
t.f = arguments.f or "make.lua" ; arguments.f = nil
t.args = arguments

if arguments.plat then
    local sp = require 'bee.subprocess'
    sp.setenv("LuaMakePlatform", arguments.plat)
else
    arguments.plat = (function ()
        if os.getenv "LuaMakePlatform" then
            return os.getenv "LuaMakePlatform"
        end
        return require "plat"
    end)()
end

assert(arguments.plat == "msvc"
    or arguments.plat == "mingw"
    or arguments.plat == "linux"
    or arguments.plat == "macos"
)

do
    if arguments.plat == "msvc" or arguments.plat == "mingw" then
        if not arguments.target then
            arguments.target = string.packsize "T" == 8 and "x64" or "x86"
        end
        assert(arguments.target == "x64" or arguments.target == "x86")
    end
end

arguments.mode = arguments.mode or "release"
arguments.crt = arguments.crt or "dynamic"

return t
