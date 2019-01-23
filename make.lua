local lm = require 'luamake'

lm.rootdir = 'lua'

if lm.plat == 'msvc' then
    local ninja = "..\\..\\tools\\ninja.exe"
    lm:build "msvc" {
        "cmd.exe", "/C",
        "cd", "3rd/bee.lua", "&&",
        "make\\lua.exe", "make\\msvc-init.lua",
        pool = "console",
    }
    lm:build "bee" {
        "cmd.exe", "/C",
        "cd", "3rd/bee.lua", "&&",
        "make\\lua.exe", "make\\msvc.lua",
        ninja, "-f", "build\\msvc\\msvc-init.ninja",
        deps = "msvc",
        pool = "console",
    }
    lm:build "copy_bee_1" {
        "cmd.exe", "/C", "copy", "/Y", "3rd\\bee.lua\\bin\\msvc_x86_release\\bootstrap.exe", "luamake.exe",
        deps = "bee"
    }
    lm:build "copy_bee_2" {
        "cmd.exe", "/C", "copy", "/Y", "3rd\\bee.lua\\bin\\msvc_x86_release\\bee.dll", "bee.dll",
        deps = "bee"
    }
    lm:build "copy_bee_3" {
        "cmd.exe", "/C", "copy", "/Y", "3rd\\bee.lua\\bin\\msvc_x86_release\\lua54.dll", "lua54.dll",
        deps = "bee"
    }
else
    local ninja = "ninja"
    lm:build "bee" {
        "cd", "3rd/bee.lua", "&&", ninja, "-f", "ninja/"..lm.plat..".ninja",
        pool = "console",
    }

    local exe = (lm.plat == 'mingw') and ".exe" or ""
    local dll = (lm.plat == 'mingw') and ".dll" or ".so"

    lm:build "copy_bee_1" {
       "cp", "3rd/bee.lua/bin/"..lm.plat.."_release/bootstrap"..exe, "luamake"..exe,
        deps = "bee"
    }
    lm:build "copy_bee_2" {
        "cp", "3rd/bee.lua/bin/"..lm.plat.."_release/bee"..dll, "bee"..dll,
        deps = "bee"
    }
    if lm.plat == 'mingw' then
        lm:build "copy_bee_3" {
            "cp", "3rd/bee.lua/bin/"..lm.plat.."_release/lua54"..dll, "lua54"..dll,
            deps = "bee"
        }
    end
end
