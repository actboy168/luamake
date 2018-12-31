local lm = require 'luamake'
local platform = require 'bee.platform'

lm.rootdir = 'lua'

if platform.OS == 'Windows' then
   lm:shared_library 'lua54.dll' {
      sources = {
         "*.c",
         "!lua.c",
         "!luac.c",
      },
      defines = {
         "LUA_BUILD_AS_DLL"
      },
   }
   lm:executable 'lua.exe' {
      deps = {
         "lua54.dll",
      },
      sources = {
         "lua.c"
      }
   }
   --lm:executable 'luac.exe' {
   --   sources = {
   --      "*.c",
   --      "!lua.c",
   --      "!lopcodes.c",
   --   }
   --}
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
   --lm:executable 'luac' {
   --   sources = {
   --      "*.c",
   --      "!lua.c",
   --      "!lopcodes.c",
   --   },
   --   defines = { "LUA_USE_LINUX" },
   --   links = { "m", "dl" },
   --}
end
