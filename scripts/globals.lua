local arguments = require "arguments"

local globals = {}

for k, v in pairs(arguments.args) do
    globals[k] = v
end

globals.mode = globals.mode or "release"
globals.crt = globals.crt or "dynamic"

globals.hostos = globals.hostos or require "bee.platform".os
globals.hostshell = globals.hostshell or (function ()
    if globals.hostos == "windows" then
        if os.getenv "MSYSTEM" then
            return "sh"
        end
        return "cmd"
    end
    return "sh"
end)()
globals.compiler = globals.compiler or (function ()
    if globals.hostshell == "cmd" then
        return "msvc"
    elseif globals.hostos == "linux" or globals.hostos == "windows" then
        return "gcc"
    end
    return "clang"
end)()
globals.os = globals.os or (function ()
    if globals.compiler == "emcc" then
        return "browser"
    end
    return globals.hostos
end)()
globals.arch = globals.arch or (function ()
    if globals.os == "windows" then
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
globals.rootdir = "."
globals.workdir = "."

return globals
