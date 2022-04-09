local fs = require "bee.filesystem"
local fsutil = require "fsutil"

local RawCommand = {
    lua = true,
    test = true,
    help = true,
}

local function command(what)
    local path = assert(package.searchpath("command."..what, package.path))
    dofile(path)
end

WORKDIR = fs.current_path():string()

if RawCommand[arg[1]] then
    command(arg[1])
else
    local arguments = require "arguments"
    if arguments.C then
        if fs.path(arguments.C):is_absolute() then
            WORKDIR = fsutil.normalize(arguments.C)
        else
            WORKDIR = fsutil.normalize(WORKDIR, arguments.C)
        end
        fs.current_path(fs.path(WORKDIR))
    end
    command(arguments.what)
end
