local util = require "util"
local globals = require "globals"
package.cpath = string.gsub([[${luamake}/?.${extension};./${builddir}/bin/?.${extension}]], "%$%{([^}]*)%}", {
    luamake = MAKEDIR:string(),
    builddir = globals.builddir,
    extension = package.cpath:match '[/\\]%?%.([a-z]+)',
})

table.insert(arg, 2, "test.lua")
util.command "lua"
