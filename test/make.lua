local lm = require 'luamake'

lm.rootdir = 'lua'

if lm.plat == "msvc" or lm.plat == "mingw" then
   lm:shared_library 'lua54' {
      sources = {
         "*.c",
         "!lua.c",
         "!luac.c",
         "!testes/*.c",
      },
      defines = "LUA_BUILD_AS_DLL"
   }
   lm:executable 'lua' {
      deps = "lua54",
      sources = "lua.c"
   }
elseif lm.plat == 'macos' then
   lm:executable 'lua' {
      sources = {
         "*.c",
         "!luac.c",
         "!testes/*.c",
      },
      defines = "LUA_USE_MACOSX",
      links = { "m", "dl" },
   }
else
   lm:executable 'lua' {
      sources = {
         "*.c",
         "!luac.c",
         "!testes/*.c",
      },
      ldflags = "-Wl,-E",
      defines = "LUA_USE_LINUX",
      links = { "m", "dl" },
   }
end

lm.rootdir = 'lpeglabel'
lm:lua_library 'lpeglabel' {
   sources = "*.c"
}

lm:build "test" {
   "$luamake", "lua", "test.lua", "$bin",
   deps = { "lpeglabel", "lua" }
}
