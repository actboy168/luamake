local sim = require 'simulator'
local lm = require 'luamake'

local sandbox = require "sandbox"
assert(sandbox(WORKDIR:string(), ARGUMENTS.f or 'make.lua', function(name, mode)
    local f, err = io.open(name, mode)
    if f then
        lm:add_script(name)
    end
    return f, err
end, { luamake = sim() }))(table.unpack(arg))

lm:finish()
