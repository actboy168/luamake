local lm = require 'luamake'
lm.rootdir = 'lpeglabel'
lm:lua_library 'lpeglabel' {
   sources = {
      "*.c"
   }
}
