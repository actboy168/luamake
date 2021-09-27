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
    local k = arg[i]
    if k:sub(1, 1) == '-' then
        if k:sub(2, 2) == '-' then
            k = k:sub(3)
        else
            k = k:sub(2)
        end
        if arg[i+1] ~= nil and arg[i+1]:sub(1, 1) ~= '-' then
            i = i + 1
            arguments[k] = arg[i]
        else
            arguments[k] = "on"
        end
    else
        targets[#targets+1] = k
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
t.C = arguments.C ; arguments.C = nil
t.f = arguments.f ; arguments.f = nil
t.args = arguments

if arguments.e then
    local expr = arguments.e
    arguments.e = nil
    assert(load(expr, "=(command line)"))()
end

return t
