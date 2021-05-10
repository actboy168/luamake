local util = require "util"
local fs = require "bee.filesystem"
local RawCommand = {
    lua = true,
    test = true,
    help = true,
}
if RawCommand[arg[1]] then
    WORKDIR = fs.current_path()
    util.command(arg[1])
else
    local arguments = require "arguments"
    local globals = require "globals"
    WORKDIR = arguments.C and fs.absolute(fs.path(arguments.C)) or fs.current_path()
    fs.current_path(WORKDIR)
    local mt = debug.getmetatable(fs.path())
    local rawtostring = mt.__tostring
    function mt:__tostring()
        local path = rawtostring(self)
        if globals.hostshell == "cmd" then
            path = path:gsub('/', '\\')
        else
            path = path:gsub('\\', '/')
        end
        return path
    end
    util.command(arguments.what)
end
