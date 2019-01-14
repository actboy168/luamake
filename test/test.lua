require 'bee'
local subprocess = require 'bee.subprocess'
local platform = require 'bee.platform'
local fs = require 'bee.filesystem'

local CWD = fs.current_path()

local lua, cpath
if platform.OS == "Windows" then
    lua = CWD / "build" / "bin" / "lua.exe"
    cpath = "build/bin/?.dll"
else
    lua = CWD / "build" / "bin" / "lua"
    cpath = "build/bin/?.so"
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
