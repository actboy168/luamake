local fs = require "bee.filesystem"
local RawCommand = {
    lua = true,
    test = true,
    help = true,
}

local function command(what)
    local path = assert(package.searchpath("command."..what, package.path))
    dofile(path)
end

if RawCommand[arg[1]] then
    WORKDIR = fs.current_path()
    command(arg[1])
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
    command(arguments.what)
end
