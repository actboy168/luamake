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
        return "."
    end
    local s = {}
    for _ in ipairs(rbase) do
        s[#s+1] = '..'
    end
    for _, e in ipairs(rpath) do
        s[#s+1] = e
    end
    return table.concat(s, '/')
end

function fsutil.absolute(path, base)
    return fs.path(fsutil.normalize((base / path):string()))
end

function fsutil.quotearg(s)
    if #s == 0 then
        return '""'
    end
    if not s:find(' \t\"', 1, true) then
        return s
    end
    if not s:find('\"\\', 1, true) then
        return '"'..s..'"'
    end
    local quote_hit = true
    local t = {}
    t[#t+1] = '"'
    for i = #s, 1, -1 do
        local c = s:sub(i,i)
        t[#t+1] = c
        if quote_hit and c == '\\' then
            t[#t+1] = '\\'
        elseif c == '"' then
            quote_hit = true
            t[#t+1] = '\\'
        else
            quote_hit = false
        end
    end
    t[#t+1] = '"'
    for i = 1, #t // 2 do
        local tmp = t[i]
        t[i] = t[#t-i+1]
        t[#t-i+1] = tmp
    end
    return table.concat(t)
end

return fsutil
