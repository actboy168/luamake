local fs = require "bee.filesystem"

local RawCommand = {
    lua = true,
    test = true,
    help = true,
    shell = true,
}

local function command(what)
    local path = assert(package.searchpath("command."..what, package.path))
    dofile(path)
end

WORKDIR = fs.current_path():string()

if RawCommand[arg[1]] then
    command(arg[1])
else
    local fsutil = require "fsutil"
    local arguments = require "arguments"
    if arguments.C then
        WORKDIR = fsutil.absolute(WORKDIR, arguments.C)
        fs.current_path(WORKDIR)
    end
    command(arguments.what)
end
