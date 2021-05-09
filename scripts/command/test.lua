local util = require "util"
local globals = require "globals"
package.cpath = string.gsub([[./${builddir}/bin/?.${extension}]], "%$%{([^}]*)%}", {
    builddir = globals.builddir,
    extension = package.cpath:match '[/\\]%?%.([a-z]+)',
})

table.insert(arg, 2, "test.lua")
util.command "lua"
