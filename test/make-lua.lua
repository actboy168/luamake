local lm = require 'luamake'
local platform = require 'bee.platform'

lm.rootdir = 'lua'

if platform.OS == 'Windows' then
   lm:shared_library 'lua54' {
      sources = {
         "*.c",
         "!lua.c",
         "!luac.c",
      },
      defines = {
         "LUA_BUILD_AS_DLL"
      },
   }
   lm:executable 'lua' {
      deps = {
         "lua54",
      },
      sources = {
         "lua.c"
      }
   }
elseif platform.OS == 'macOS' then
   lm:executable 'lua' {
      sources = {
         "*.c",
         "!luac.c",
      },
      defines = { "LUA_USE_MACOSX" },
      links = { "m", "dl" },
   }
else
   lm:executable 'lua' {
      sources = {
         "*.c",
         "!luac.c",
      },
      ldflags = { "-Wl,-E" },
      defines = { "LUA_USE_LINUX" },
      links = { "m", "dl" },
   }
end
