local globals = require "globals"
package.cpath = string.gsub([[${luamake}/?.${extension};./${builddir}/bin/?.${extension}]], "%$%{([^}]*)%}", {
    luamake = package.procdir,
    builddir = globals.builddir,
    extension = package.cpath:match "[/\\]%?%.([a-z]+)",
})

table.insert(arg, 2, "test.lua")

local command = require "command"
command.run "lua"
