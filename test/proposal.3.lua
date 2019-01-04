require "luamake"
local platform = require "bee.platform"

default "" do
    rootdir = "lua"
end

if platform.OS == "Windows" then
    shared_library "lua54" do
        source = "*.c"
        source = "!lua.c"
        source = "!luac.c"
        define = "LUA_BUILD_AS_DLL"
    end
    executable "lua" do
        deps   = "lua54"
        source = "lua.c"
    end
else
    executable "lua" do
        source = "*.c"
        source = "!luac.c"
        if platform.OS == "macOS" then
            ldflag = "-Wl,-E"
            define = "LUA_USE_LINUX"
        else
            define = "LUA_USE_MACOSX"
        end
        link = "m"
        link = "dl"
    end
end

default "" do
    rootdir = "lpeglabel"
end

lua_library "lpeglabel" do
    source = "*.c"
end
