local util = require "util"
local plat = require "plat"
package.cpath = string.gsub([[./build/${platform}/bin/?.${extension}]], "%$%{([^}]*)%}", {
    platform = plat,
    extension = package.cpath:match '[/\\]%?%.([a-z]+)',
})

table.insert(arg, 2, "test.lua")
util.command "lua"
