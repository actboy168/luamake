local lm = require 'luamake'

local isWindows = lm.os == 'windows'
local exe = isWindows and ".exe" or ""
local dll = isWindows and ".dll" or ".so"

lm:import "3rd/bee.lua/make.lua"

lm:copy "copy_bootstrap" {
    input = "$bin/bootstrap"..exe,
    output = "luamake"..exe,
    deps = "bootstrap",
}
lm:copy "copy_bee" {
    input = "$bin/bee"..dll,
    output = "bee"..dll,
    deps = "bee"
}
if isWindows then
    lm:copy "copy_lua54" {
        input = "$bin/lua54"..dll,
        output = "lua54"..dll,
        deps = "lua54"
    }
end

lm:default {
    "test",
    "copy_bootstrap",
    "copy_bee",
    isWindows and "copy_lua54",
}
