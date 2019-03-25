local n = #arg
for i = 0, n do
    arg[i-2] = arg[i]
end
arg[n] = nil
arg[n-1] = nil

local sandbox = require "sandbox"
assert(sandbox(WORKDIR:string(), arg[0], io.open, {
    msvc = require "msvc_helper",
}))(table.unpack(arg))
