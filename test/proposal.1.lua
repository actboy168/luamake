require "luamake"
local platform = require "bee.platform"

rootdir = "lua"

if platform.OS == "Windows" then
    for _ in shared_library "lua54" do
        source = "*.c"
        source = "!lua.c"
        source = "!luac.c"
        define = "LUA_BUILD_AS_DLL"
    end
    for _ in executable "lua" do
        deps   = "lua54"
        source = "lua.c"
    end
else
    for _ in executable "lua" do
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

rootdir = "lpeglabel"
for _ in lua_library "lpeglabel" do
    source = "*.c"
end
