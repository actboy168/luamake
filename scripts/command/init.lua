local sim = require 'simulator'
local arguments = require "arguments"

sim:dofile(WORKDIR:string(), arguments.f)
sim:finish()
