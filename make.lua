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
    lm:phony {
        deps = "copy_luamake",
        output = "bee.lua/bootstrap/forward_lua.lua"
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
