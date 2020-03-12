local sim = require 'simulator'
local arguments = require "arguments"

sim:dofile(WORKDIR:string(), arguments.f or 'make.lua')
sim:finish()
