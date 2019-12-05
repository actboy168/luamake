local output = ...

require 'bee'
local fs = require 'bee.filesystem'
local sp = require 'bee.subprocess'

local function createfile(filename, content)
    local f = assert(io.open(filename:string(), 'w'))
    if content then
        f:write(content)
    end
    f:close()
end

local testdir = fs.path 'temp'
fs.create_directories(testdir)
createfile(testdir / 'test.h')
createfile(testdir / 'test.c', '#include "test.h"')
local process = assert(sp.shell {
    'cl', '/showIncludes', '/nologo', '-c', 'test.c',
    cwd = testdir,
    stdout = true,
    stderr = true,
})
local prefix
for line in process.stdout:lines() do
    local m = line:match('[^:]+:[^:]+:')
    if m then
        prefix = m
        break
    end
end
process.stdout:close()
process.stderr:close()
process:wait()
fs.remove_all(testdir)
assert(prefix, "can't find msvc.")

fs.create_directories(fs.path(output):parent_path())

local template = [[
builddir = build/msvc
msvc_deps_prefix = %s
subninja ninja/msvc.ninja
]]

assert(
    assert(
        io.open(output, 'wb')
    ):write(template:format(prefix))
):close()
