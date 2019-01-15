local fs = require 'bee.filesystem'
local util = require 'util'

local build_ninja = util.script()

if not fs.exists(build_ninja) then
    util.command 'init'
end

util.ninja {}
