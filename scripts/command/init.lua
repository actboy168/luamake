local lm = require 'luamake'

local sandbox = require "sandbox"
sandbox(WORKDIR:string(), ARGUMENTS.f or 'make.lua', function(name, mode)
    local f, err = io.open(name, mode)
    if f then
        lm:add_script(name)
    end
    return f, err
end, { luamake = lm })()

lm:close()
