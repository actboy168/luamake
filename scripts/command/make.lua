local fs = require 'bee.filesystem'
local util = require 'util'

local build_ninja = (WORKDIR / 'build' / (ARGUMENTS.f or 'make.lua')):replace_extension(".ninja")

if not fs.exists(build_ninja) then
    util.command('init')
end

util.ninja {}
