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

lm:import "bee.lua/make.lua"

lm:copy "copy_luamake" {
    inputs = "$bin/bootstrap"..exe,
    outputs = "luamake"..exe,
    deps = "bootstrap",
}

if isWindows then
    lm:runlua "forward_lua" {
        script = "compile/lua/forward_lua.lua",
        args = { "@bee.lua/3rd/lua/", "$out", "luamake.exe" },
        inputs = {
            "bee.lua/3rd/lua/lua.h",
            "bee.lua/3rd/lua/lauxlib.h",
            "bee.lua/3rd/lua/lualib.h",
        },
        outputs = "compile/lua/forward_lua.c",
        deps = "copy_luamake",
    }
    lm:dll "lua54" {
        sources = "compile/lua/forward_lua.c",
    }
    lm:copy "copy_lua54" {
        inputs = "$bin/lua54.dll",
        outputs = "tools/lua54.dll",
        deps = "lua54"
    }
end

lm:phony "notest" {
    deps = {
        "copy_luamake",
        isWindows and "copy_lua54",
    }
}

lm:default {
    "test",
    "notest",
}
