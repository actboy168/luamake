local lm = require 'luamake'

local isWindows = lm.os == 'windows'
local exe = isWindows and ".exe" or ""
local dll = isWindows and ".dll" or ".so"

lm.EXE_NAME = "luamake"
lm:import "3rd/bee.lua/make.lua"

lm:copy "copy_luamake" {
    input = "$bin/luamake"..exe,
    output = "luamake"..exe,
    deps = "luamake",
}

lm:default {
    "test",
    "copy_luamake",
}
