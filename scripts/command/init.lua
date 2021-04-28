local sim = require 'simulator'
local arguments = require "arguments"

sim:dofile(WORKDIR / arguments.f)
sim:finish()
