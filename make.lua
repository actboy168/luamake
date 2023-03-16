local lm = require 'luamake'
lm:required_version "1.0"

local isWindows = lm.os == 'windows'

if lm.prebuilt == nil then
    print("Please use `" .. (isWindows and [[.\compile\install.bat]] or [[./compile/install.sh]]) .. "`.")
    return
end

local exe = isWindows and ".exe" or ""
local dll = isWindows and ".dll" or ".so"

lm:import "bee.lua/make.lua"

lm:copy "copy_luamake" {
    input = "$bin/bootstrap"..exe,
    output = "luamake"..exe,
    deps = "bootstrap",
}

if isWindows then
    lm:runlua "forward_lua" {
        script = "bee.lua/bootstrap/forward_lua.lua",
        args = {"@bee.lua/3rd/lua/", "$out", "luamake.exe", lm.compiler},
        input = {
            "bee.lua/bootstrap/forward_lua.lua",
            "bee.lua/3rd/lua/lua.h",
            "bee.lua/3rd/lua/lauxlib.h",
            "bee.lua/3rd/lua/lualib.h",
        },
        output = "bee.lua/bootstrap/forward_lua.h",
        deps = "copy_luamake",
    }
    lm:phony {
        input = "bee.lua/bootstrap/forward_lua.h",
        output = "bee.lua/bootstrap/forward_lua.c",
    }
    lm:shared_library "lua54" {
        includes = "bee.lua/bootstrap",
        sources = "bee.lua/bootstrap/forward_lua.c",
        ldflags = "$obj/bootstrap.lib",
        deps = {
            "bootstrap",
        }
    }
    lm:copy "copy_lua54" {
        input = "$bin/lua54"..dll,
        output = "tools/lua54"..dll,
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
