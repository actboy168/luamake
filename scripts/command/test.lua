local util = require "util"
local plat = (function ()
    local platform = require "bee.platform"
    if platform.OS == "Windows" then
        if os.getenv "MSYSTEM" then
            return "mingw"
        end
        return "msvc"
    elseif platform.OS == "Linux" then
        return "linux"
    elseif platform.OS == "macOS" then
        return "macos"
    end
end)()
package.cpath = string.gsub([[./build/${platform}/bin/?.${extension}]], "%$%{([^}]*)%}", {
    platform = plat,
    extension = package.cpath:match '[/\\]%?%.([a-z]+)',
})

table.insert(arg, 2, "test.lua")
util.command "lua"
