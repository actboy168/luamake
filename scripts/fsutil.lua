local fs = require 'bee.filesystem'
local platform = require 'bee.platform'

local fsutil = {}

local function normalize(p)
    local pattern = platform.OS == "Windows" and '[^/\\]*' or '[^/]*'
    local stack = {}
    p:gsub(pattern, function (w)
        if #w == 0 and #stack ~= 0 then
        elseif w == '..' and #stack ~= 0 and stack[#stack] ~= '..' then
            stack[#stack] = nil
        elseif w ~= '.' then
            stack[#stack + 1] = w
        end
    end)
    return stack
end

function fsutil.normalize(p)
    return table.concat(normalize(p), '/')
end

function fsutil.relative(path, base)
    local equal = platform.OS ~= "Linux"
        and (function(a, b) return a:lower() == b:lower() end)
        or (function(a, b) return a == b end)
    local rpath = normalize(path)
    local rbase = normalize(base)
    if platform.OS == "Windows" and not equal(rpath[1], rbase[1]) then
        return table.concat(rpath, '/')
    end
    while #rpath > 0 and #rbase > 0 and equal(rpath[1], rbase[1]) do
        table.remove(rpath, 1)
        table.remove(rbase, 1)
    end
    if #rpath == 0 and #rbase== 0 then
        return "./"
    end
    local s = {}
    for _ in ipairs(rbase) do
        s[#s+1] = '..'
    end
    if #s == 0 then
        s[#s+1] = '.'
    end
    for _, e in ipairs(rpath) do
        s[#s+1] = e
    end
    return table.concat(s, '/')
end

function fsutil.absolute(path, base)
    return fs.path(fsutil.normalize((base / path):string()))
end

return fsutil
