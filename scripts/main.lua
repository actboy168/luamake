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
    WORKDIR = arguments.C and fs.absolute(fs.path(arguments.C)) or fs.current_path()
    fs.current_path(WORKDIR)
    util.command(arguments.what)
end
