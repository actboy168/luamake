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
    if arguments.C then
        WORKDIR = fs.absolute(fs.path(arguments.C)):lexically_normal()
        fs.current_path(WORKDIR)
    else
        WORKDIR = fs.current_path()
    end
    local mt = debug.getmetatable(fs.path())
    local rawtostring = mt.__tostring
    function mt:__tostring()
        return rawtostring(self):gsub('\\', '/')
    end
    command(arguments.what)
end
