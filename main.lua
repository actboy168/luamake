ARGUMENTS = {}

local what = arg[1]
if what == nil then
    what = 'make'
else
    local i = 2
    if what == 'lua' then
        i = #arg + 1
    elseif what:sub(1, 1) == '-' then
        what = 'make'
        i = 1
    end
    while i <= #arg do
        if arg[i]:sub(1, 1) == '-' then
            local k = arg[i]:sub(2)
            i = i + 1
            ARGUMENTS[k] = arg[i]
        else
            error(('unknown option: %s'):format(arg[i]))
        end
        i = i + 1
    end
end

require 'bee'
local fs = require 'bee.filesystem'

MAKEDIR = fs.exe_path():parent_path()
WORKDIR = ARGUMENTS.C and fs.absolute(fs.path(ARGUMENTS.C)) or fs.current_path()

package.path = (MAKEDIR / "scripts" / "?.lua"):string()

local util = require 'util'
util.command(what)
