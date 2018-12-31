local lm = require 'luamake'

dofile((WORKDIR / (ARGUMENTS.f or 'make.lua')):string())

lm:close()
