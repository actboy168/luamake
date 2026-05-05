table.insert(arg, 2, "test.lua")

local command = require "command"
command.run "lua"
