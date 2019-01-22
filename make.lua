local lm = require 'luamake'

lm.rootdir = 'lua'

if lm.plat == 'msvc' then
    local ninja = "..\\..\\tools\\ninja.exe"
    lm:build "bee" {
        "cmd.exe", "/C", "cd", "3rd/bee.lua", "&&", ninja, "-f", "build/"..lm.plat.."/make.ninja",
    }
    lm:build "copy_bee_1" {
        "cmd.exe", "/C", "copy", "/Y", "3rd\\bee.lua\\bin\\msvc_x86_release\\bootstrap.exe", "luamake.exe",
        deps = "bee"
    }
    lm:build "copy_bee_2" {
        "cmd.exe", "/C", "copy", "/Y", "3rd\\bee.lua\\bin\\msvc_x86_release\\bee.dll", "bee.dll",
        deps = "bee"
    }
else
    local ninja = "ninja"
    lm:build "bee" {
        "cd", "3rd/bee.lua", "&&", ninja, "-f", "build/"..lm.plat.."/make.ninja",
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
end
