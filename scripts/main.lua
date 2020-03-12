local arguments = require "arguments"
local fs = require 'bee.filesystem'
WORKDIR = arguments.C and fs.absolute(fs.path(arguments.C)) or fs.current_path()
fs.current_path(WORKDIR)
local util = require 'util'
util.command(arguments.what)
