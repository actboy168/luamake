local lm = require 'luamake'
local platform = require 'bee.platform'

lm.rootdir = 'lua'

if platform.OS == 'Windows' then
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
elseif platform.OS == 'macOS' then
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
   "$luamake", "lua", "test.lua",
   deps = { "lpeglabel", "lua" }
}
