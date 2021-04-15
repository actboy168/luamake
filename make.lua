local lm = require 'luamake'

local isWindows = lm.plat == 'mingw' or lm.plat == 'msvc'
local exe = isWindows and ".exe" or ""
local dll = isWindows and ".dll" or ".so"

lm:import "3rd/bee.lua/make.lua"

lm:build "copy_bootstrap" {
    "{COPY}", "$bin/bootstrap"..exe, "luamake"..exe,
     deps = "bootstrap"
}
lm:build "copy_bee" {
    "{COPY}", "$bin/bee"..dll, "bee"..dll,
    deps = "bee"
}
if isWindows then
    lm:build "copy_lua54" {
        "{COPY}", "$bin/lua54"..dll, "lua54"..dll,
        deps = "lua54"
    }
end

lm:default {
    "test",
    "copy_bootstrap",
    "copy_bee",
    isWindows and "copy_lua54",
}
