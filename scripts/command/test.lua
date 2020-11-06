local sandbox = require "util".sandbox
local arguments = require "arguments"

package.cpath = string.gsub([[./build/${platform}/bin/?.${extension}]], "%$%{([^}]*)%}", {
    platform = arguments.plat,
    extension = package.cpath:match '[/\\]%?%.([a-z]+)',
})

sandbox "test.lua"
