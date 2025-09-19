local lm = require "luamake"
lm:required_version "1.0"

local isWindows = lm.os == "windows"

if lm.prebuilt == nil then
    print("Please use `"..(isWindows and [[.\compile\install.bat]] or [[./compile/install.sh]]).."`.")
    os.exit(false)
    return
end

if lm.lua2c then
    require "compile.lua2c"
end

local exe = isWindows and ".exe" or ""

lm.fast_setjmp = "off"

lm:import "bee.lua/make.lua"

lm:lua_exe "luamake" {
    deps = {
        "source_bee",
        "source_lua",
        "source_bootstrap",
    },
    sources = lm.lua2c and {
        "compile/lua/lua2c.c"
    },
    windows = {
        sources = "bee.lua/bootstrap/bootstrap.rc",
    },
    msvc = {
        ldflags = "/IMPLIB:$obj/luamake.lib"
    },
    mingw = {
        ldflags = "-Wl,--out-implib,$obj/luamake.lib"
    },
}

lm:copy "copy_mainlua" {
    inputs = "bee.lua/bootstrap/main.lua",
    outputs = "$bin/main.lua",
}

lm:copy "copy_luamake" {
    inputs = "$bin/luamake"..exe,
    outputs = "luamake"..exe,
    deps = "luamake",
}

lm:build "luamake_test" {
    args = { "luamake"..exe, "lua", "@bee.lua/test/test.lua" },
    description = "Run test.",
    pool = "console",
    deps = { "copy_luamake", "copy_mainlua" },
}

if isWindows then
    lm:runlua "forward_lua" {
        script = "compile/lua/forward_lua.lua",
        args = { "@bee.lua/3rd/lua54/", "$out", "luamake.exe" },
        inputs = {
            "bee.lua/3rd/lua54/lua.h",
            "bee.lua/3rd/lua54/lauxlib.h",
            "bee.lua/3rd/lua54/lualib.h",
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
    "luamake_test",
    "notest",
}
