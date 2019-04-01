local fs = require 'bee.filesystem'
local util = require 'util'

local build_ninja = util.script()

if fs.exists(build_ninja) then
    util.command 'clean'
end
util.command 'init'
util.ninja {}
