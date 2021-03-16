local lm = require 'luamake'

lm.rootdir = 'lua'

local isWindows = lm.plat == 'mingw' or lm.plat == 'msvc'
local exe = isWindows and ".exe" or ""
local dll = isWindows and ".dll" or ".so"

if lm.plat == 'msvc' then
    local ninja = "..\\..\\tools\\ninja.exe"
    lm:build "msvc" {
        "cmd.exe", "/C",
        "cd", "tools\\msvc", "&&",
        "lua.exe", "init.lua", "..\\..\\3rd\\bee.lua\\build\\msvc\\msvc-init.ninja",
        pool = "console",
    }
    lm:build "bee" {
        "cmd.exe", "/C",
        "cd", "3rd/bee.lua", "&&",
        ninja, "-f", "build\\msvc\\msvc-init.ninja",
        deps = "msvc",
        pool = "console",
    }
else
    local ninja = "ninja"
    lm:build "bee" {
        "cd", "3rd/bee.lua", "&&", ninja, "-f", "ninja/"..lm.plat..".ninja",
        pool = "console",
    }
end

lm:build "copy_bee_1" {
    "{COPY}", "3rd/bee.lua/$bin/bootstrap"..exe, "luamake"..exe,
     deps = "bee"
}
lm:build "copy_bee_2" {
    "{COPY}", "3rd/bee.lua/$bin/bee"..dll, "bee"..dll,
    deps = "bee"
}
if isWindows then
    lm:build "copy_bee_3" {
        "{COPY}", "3rd/bee.lua/$bin/lua54"..dll, "lua54"..dll,
        deps = "bee"
    }
end
