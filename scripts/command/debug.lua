local globals = require "globals"
local sp = require "bee.subprocess"
if globals.compiler ~= "msvc" then
    error "unimplemented"
    return
end
local msvc = require "msvc"
local devenv = msvc:installpath() / "Common7" / "IDE" / "devenv.exe"
local args = {}
for i = 2, #arg do
    args[i-1] = arg[i]
end
sp.spawn {
    devenv, "/debugexe", [[./build/msvc/bin/lua.exe]], args
}
