local bin = ...

require 'bee'
local subprocess = require 'bee.subprocess'
local platform = require 'bee.platform'
local fs = require 'bee.filesystem'

local CWD = fs.current_path()
local bindir = fs.absolute(fs.path(bin))

local lua, cpath
if platform.OS == "Windows" then
    lua = bindir / "lua.exe"
    cpath = (bindir / "?.dll"):string()
else
    lua = bindir / "lua"
    cpath = (bindir / "?.so"):string()
end

local process = assert(subprocess.shell {
    lua,
    "-e", "package.path=[[lpeglabel/?.lua]]",
    "-e", ("package.cpath=[[%s]]"):format(cpath),
    CWD / "lpeglabel" / "test.lua",
    stderr = io.stderr,
    stdout = io.stdout
})
os.exit(process:wait(), true)
