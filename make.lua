local lm = require 'luamake'

local isWindows = lm.plat == 'mingw' or lm.plat == 'msvc'
local exe = isWindows and ".exe" or ""
local dll = isWindows and ".dll" or ".so"

lm:import "3rd/bee.lua/make.lua"

lm:build "copy_bee_1" {
    "{COPY}", "$bin/bootstrap"..exe, "luamake"..exe,
     deps = "bee"
}
lm:build "copy_bee_2" {
    "{COPY}", "$bin/bee"..dll, "bee"..dll,
    deps = "bee"
}
if isWindows then
    lm:build "copy_bee_3" {
        "{COPY}", "$bin/lua54"..dll, "lua54"..dll,
        deps = "bee"
    }
end

lm:default {
    "test",
    "copy_bee_1",
    "copy_bee_2",
    isWindows and "copy_bee_3",
}
