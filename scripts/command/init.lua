local dontgenerate = ...
local sim = require 'simulator'
sim:dofile(WORKDIR / "make.lua")
if not dontgenerate then
    sim:finish()
end
