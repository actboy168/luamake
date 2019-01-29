local sim = require 'simulator'

sim:dofile(WORKDIR:string(), ARGUMENTS.f or 'make.lua')
sim:finish()
