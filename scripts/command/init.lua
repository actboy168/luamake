local lm = require 'luamake'

require "common.require"
dofile((WORKDIR / (ARGUMENTS.f or 'make.lua')):string())

lm:close()
