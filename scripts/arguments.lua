local t = {}
local arguments = {}
local targets = {}
local what = 'remake'

local function has_command(what)
    local path = package.searchpath("command."..what, package.path)
    return path ~= nil
end

local i = 1
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
if #targets > 0 then
    if has_command(targets[1]) then
        what = table.remove(targets, 1)
    end
end

t.what = what
t.targets = targets
t.C = arguments.C               ; arguments.C = nil
t.args = arguments

if arguments.e then
    local expr = arguments.e
    arguments.e = nil
    assert(load(expr, "=(command line)"))()
end

return t
