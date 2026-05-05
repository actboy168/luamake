local globals = require "globals"

local fsutil = {}

local isWindows <const> = globals.hostos == "windows"
local isMacOS <const> = globals.hostos == "macos"
local PathSpilt <const> = isWindows and "[^/\\]+" or "[^/]+"
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
        if w == ".." and #stack ~= 0 and stack[#stack] ~= ".." then
            stack[#stack] = nil
        elseif w ~= "." then
            stack[#stack+1] = w
        end
    end)
    return stack
end

function fsutil.join(...)
    return table.concat(table.pack(...), "/")
end

function fsutil.normalize(...)
    local path = fsutil.join(...)
    local hasRoot = path:sub(1, 1) == "/"
    local stack = normalize(path)
    if hasRoot then
        return "/"..table.concat(stack, "/")
    elseif #stack == 0 then
        return "."
    else
        return table.concat(stack, "/")
    end
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

if isWindows then
    function fsutil.is_absolute(path)
        if path:match "^%$" then
            return true
        end
        if path:match "^%a:[/\\]" then
            return true
        end
        if path:match "^[/\\][/\\][%?%.][/\\]" then
            return not path:match "^....[/\\]"
        end
        if path:match "^[/\\]%?%?[/\\]" then
            return not path:match "^....[/\\]"
        end
        if path:match "^[/\\][/\\][^/\\]" then
            return true
        end
        return false
    end
else
    function fsutil.is_absolute(path)
        if path:match "^%$" then
            return true
        end
        if path:match "^/" then
            return true
        end
        return false
    end
end

function fsutil.absolute(base, path)
    if fsutil.is_absolute(path) then
        return fsutil.normalize(path)
    end
    return fsutil.normalize(base, path)
end

function fsutil.relative(path, base)
    if base:sub(1, 1) ~= path:sub(1, 1) then
        return path
    end
    local rpath = normalize(path)
    local rbase = normalize(base)
    if isWindows and not path_equal(rpath[1], rbase[1]) then
        return table.concat(rpath, "/")
    end
    while #rpath > 0 and #rbase > 0 and path_equal(rpath[1], rbase[1]) do
        table.remove(rpath, 1)
        table.remove(rbase, 1)
    end
    if #rpath == 0 and #rbase == 0 then
        return "."
    end
    local s = {}
    for _ in ipairs(rbase) do
        s[#s+1] = ".."
    end
    for _, e in ipairs(rpath) do
        s[#s+1] = e
    end
    return table.concat(s, "/")
end

fsutil.quotearg = require "quotearg"

return fsutil
