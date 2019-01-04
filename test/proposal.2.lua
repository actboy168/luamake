require "luamake"
local platform = require "bee.platform"

rootdir = "lua"

if platform.OS == "Windows" then
    shared_library "lua54"
        source = "*.c"
        source = "!lua.c"
        source = "!luac.c"
        define = "LUA_BUILD_AS_DLL"
    end_region()
    executable "lua"
        deps   = "lua54"
        source = "lua.c"
    end_region()
else
    executable "lua"
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
    end_region()
end

rootdir = "lpeglabel"
lua_library "lpeglabel"
    source = "*.c"
end_region()
