local quotearg = require "quotearg"
local platform = require "bee.platform"

local function find_exe()
    local i = 0
    while arg[i] ~= nil do
        i = i - 1
    end
    return i + 1
end

local function update_arg()
    for i = 1, #arg do
        if arg[i] == "-e" then
            table.remove(arg, i)
            table.remove(arg, i)
            break
        end
    end

    if arg[2] == nil then
        error "Not found lua file."
    end
    arg[0] = arg[2]
    table.remove(arg, 1)
    table.remove(arg, 1)

    local idx = find_exe()
    arg[idx] = quotearg(arg[idx]).." lua"
end

update_arg()

local workdir <const> = WORKDIR
local procdir <const> = package.procdir
local ext = package.cpath:match("%.([a-z]+)$")

if platform.os == "windows" then
    package.loadlib(procdir.."/tools/lua55.dll", "*")
end

package.path = table.concat({
    workdir.."/?.lua",
    workdir.."/?/init.lua",
    procdir.."/libs/?.lua",
    package.path
}, ";")
package.cpath = table.concat({
    workdir.."/build/bin/?."..ext,
    package.cpath
}, ";")

local f, err = loadfile(arg[0])
if not f then
    error(err)
end

f(table.unpack(arg))
