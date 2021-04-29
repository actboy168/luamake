local plat = require "plat"
local sp = require "bee.subprocess"
if plat ~= "msvc" then
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
