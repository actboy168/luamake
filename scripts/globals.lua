local platform = require "bee.platform"
local arguments = require "arguments"

local globals = {}

for k, v in pairs(arguments.args) do
    globals[k] = v
end

globals.mode = globals.mode or "release"
globals.crt = globals.crt or "dynamic"

globals.os = globals.os or platform.OS:lower()
globals.compiler = globals.compiler or (function()
    if globals.os == "windows" then
        if os.getenv "MSYSTEM" then
            return "gcc"
        end
        return "msvc"
    elseif globals.os == "macos" then
        return "clang"
    end
    return "gcc"
end)()
globals.hostshell = globals.hostshell or (function()
    if globals.compiler == "msvc" then
        return "cmd"
    else
        return "sh"
    end
end)()
globals.builddir = globals.builddir or "build"

do
    if globals.os == "windows" then
        if not globals.target then
            globals.target = string.packsize "T" == 8 and "x64" or "x86"
        end
        assert(globals.target == "x64" or globals.target == "x86")
    end
end

return globals
