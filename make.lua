local lm = require "luamake"
lm:required_version "1.0"

local isWindows = lm.os == "windows"

if lm.prebuilt == nil then
    print("Please use `"..(isWindows and [[.\compile\install.bat]] or [[./compile/install.sh]]).."`.")
    os.exit(false)
    return
end

local exe = isWindows and ".exe" or ""

lm.fast_setjmp = "off"
lm.lua = "55"

lm:import "bee.lua/make.lua"

lm:copy "copy_mainlua" {
    inputs = "bee.lua/bootstrap/main.lua",
    outputs = "$bin/main.lua",
}

lm:copy "copy_luamake" {
    inputs = "$bin/bootstrap"..exe,
    outputs = "luamake"..exe,
    deps = "bootstrap",
}

if isWindows then
    lm:runlua "forward_lua" {
        script = "compile/lua/forward_lua.lua",
        args = { "@bee.lua/3rd/lua"..lm.lua.."/", "$out", "luamake.exe" },
        inputs = {
            "bee.lua/3rd/lua"..lm.lua.."/lua.h",
            "bee.lua/3rd/lua"..lm.lua.."/lauxlib.h",
            "bee.lua/3rd/lua"..lm.lua.."/lualib.h",
        },
        outputs = "compile/lua/forward_lua.c",
        deps = "copy_luamake",
    }
    lm:dll("lua"..lm.lua) {
        sources = "compile/lua/forward_lua.c",
    }
    lm:copy "copy_lua" {
        inputs = "$bin/lua"..lm.lua..".dll",
        outputs = "tools/lua"..lm.lua..".dll",
        deps = "lua"..lm.lua
    }
end

lm:phony "notest" {
    deps = {
        "copy_luamake",
        "copy_mainlua",
        isWindows and "copy_lua",
    }
}

lm:default {
    "test",
    "notest",
}
