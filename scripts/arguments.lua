local arguments = {_force={}}

local what = arg[1]
if what == nil then
    what = 'make'
else
    local i = 2
    if what == 'lua' then
        i = #arg + 1
    elseif what:sub(1, 1) == '-' then
        what = 'make'
        i = 1
    end
    while i <= #arg do
        if arg[i]:sub(1, 1) == '-' then
            local k = arg[i]:sub(2)
            i = i + 1
            arguments[k] = arg[i]
            arguments._force[k] = true
        else
            error(('unknown option: %s'):format(arg[i]))
        end
        i = i + 1
    end
end
arguments.what = what

if not arguments.arch then
    arguments.arch = string.packsize "T" == 8 and "x64" or "x86"
end

assert(arguments.arch == "x64"
    or arguments.arch == "x86"
)

if arguments.plat then
    local sp = require 'bee.subprocess'
    sp.setenv("LuaMakePlatform", arguments.plat)
else
    arguments.plat = (function ()
        if os.getenv "LuaMakePlatform" then
            return os.getenv "LuaMakePlatform"
        end
        local platform = require 'bee.platform'
        if platform.OS == "Windows" then
            if os.getenv "MSYSTEM" then
                return "mingw"
            end
            return "msvc"
        elseif platform.OS == "Linux" then
            return "linux"
        elseif platform.OS == "macOS" then
            return "macos"
        end
    end)()
end

assert(arguments.plat == "msvc"
    or arguments.plat == "mingw"
    or arguments.plat == "linux"
    or arguments.plat == "macos"
)

if not arguments.f then
    arguments.f = "make.lua"
end
assert(arguments.f)

return arguments
