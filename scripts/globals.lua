local platform = require "bee.platform"
local arguments = require "arguments"

local globals = {}

for k, v in pairs(arguments.args) do
    globals[k] = v
end

globals.mode = globals.mode or "release"
globals.crt = globals.crt or "dynamic"

globals.hostos = globals.hostos or platform.OS:lower()
globals.os = globals.os or globals.hostos
globals.compiler = globals.compiler or (function()
    if globals.hostos == "windows" then
        if os.getenv "MSYSTEM" then
            return "gcc"
        end
        return "msvc"
    elseif globals.hostos == "macos" then
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
globals.arch = globals.arch or (function ()
    if globals.hostos == "windows" then
        if string.packsize "T" == 8 then
            return "x86_64"
        else
            return "x86"
        end
    end
end)()
globals.builddir = globals.builddir or "build"
globals.bindir = globals.bindir or "$builddir/bin"
globals.objdir = globals.objdir or "$builddir/obj"

return globals
