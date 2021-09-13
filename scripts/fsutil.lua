local globals = require "globals"

local fsutil = {}

local isWindows <const> = globals.hostos == "windows"
local isMacOS <const> = globals.hostos == "macos"
local PathSpilt <const> = isWindows and '[^/\\]*' or '[^/]*'
local PathIgnoreCase <const> = isWindows or isMacOS

local path_equal; do
    if PathIgnoreCase then
        function path_equal(a, b)
            return a:lower() == b:lower()
        end
    else
        function path_equal(a, b)
            return a == b
        end
    end
end

local function normalize(p)
    local stack = {}
    p:gsub(PathSpilt, function (w)
        if #w == 0 and #stack ~= 0 then
        elseif w == '..' and #stack ~= 0 and stack[#stack] ~= '..' then
            stack[#stack] = nil
        elseif w ~= '.' then
            stack[#stack + 1] = w
        end
    end)
    return stack
end

function fsutil.join(...)
    return table.concat(table.pack(...), '/')
end

function fsutil.normalize(...)
    return table.concat(normalize(fsutil.join(...)), '/')
end

function fsutil.parent_path(path)
    return path:match "^(.+)/[^/]*$"
end

function fsutil.filename(path)
    return path:match "[/]?([^/]*)$"
end

function fsutil.stem(path)
    return path:match "[/]?([^/]*)[.][^./]*$" or path:match "[/]?([.]?[^./]*)$"
end

function fsutil.extension(path)
    return path:match "[^/]([.][^./]*)$"
end

function fsutil.relative(path, base)
    local rpath = normalize(path)
    local rbase = normalize(base)
    if isWindows and not path_equal(rpath[1], rbase[1]) then
        return table.concat(rpath, '/')
    end
    while #rpath > 0 and #rbase > 0 and path_equal(rpath[1], rbase[1]) do
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
