local fs = require 'bee.filesystem'
MAKEDIR = fs.path('.')

local msvc = require 'msvc_helper'
local arch = nil
local winsdk = nil
local env = msvc.environment(arch, winsdk)
local prefix = msvc.prefix(env)

local cwd = fs.exe_path():parent_path():parent_path()
local outdir = cwd / 'build' / 'msvc'
local output = outdir / 'msvc-init.ninja'
fs.create_directories(outdir)

local template = [[
builddir = build/msvc
msvc_deps_prefix = %s
subninja ninja/msvc.ninja
]]

assert(
    assert(
        io.open(output:string(), 'wb')
    ):write(template:format(prefix))
):close()
