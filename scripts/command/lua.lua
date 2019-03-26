local n = #arg
for i = 0, n do
    arg[i-2] = arg[i]
end
arg[n] = nil
arg[n-1] = nil

local util = require "util"
local sandbox = require "sandbox"
local env = util.plat == 'msvc' and {
    msvc = require "msvc_helper",
}
assert(sandbox(WORKDIR:string(), arg[0], io.open, env))(table.unpack(arg))
