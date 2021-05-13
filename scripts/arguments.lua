local t = {}
local arguments = {}
local targets = {}
local what = arg[1]

local function has_command(what)
    local path = package.searchpath(what, (MAKEDIR / "scripts" / "command" / "?.lua"):string())
    return path ~= nil
end

if what == nil then
    what = 'remake'
else
    local i = 2
    if not has_command(what) then
        what = 'remake'
        i = 1
    end
    while i <= #arg do
        if arg[i]:sub(1, 1) == '-' then
            local k = arg[i]:sub(2)
            i = i + 1
            arguments[k] = arg[i]
        else
            targets[#targets+1] = arg[i]
        end
        i = i + 1
    end
end

t.what = what
t.targets = targets
t.C = arguments.C               ; arguments.C = nil
t.args = arguments

return t
