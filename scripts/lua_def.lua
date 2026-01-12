local fs = require "bee.filesystem"

local function getvalue(str, key)
    local value = str:match("^%s*#%s*define%s*"..key.."%s*([0-9]+)%s*$")
    if value then
        return tonumber(value)
    end
end

local function parse(folder)
    local version
    local version_major
    local version_minor
    local export = {}
    for line in io.lines(folder.."/lua.h") do
        version = version or getvalue(line, "LUA_VERSION_NUM")
        version_major = version_major or getvalue(line, "LUA_VERSION_MAJOR_N")
        version_minor = version_minor or getvalue(line, "LUA_VERSION_MINOR_N")
        local api = line:match "^%s*LUA_API[%w%s%*_]+%(([%w_]+)%)"
        if api then
            export[#export+1] = api
        end
    end
    for line in io.lines(folder.."/lauxlib.h") do
        local api = line:match "^%s*LUALIB_API[%w%s%*_]+%(([%w_]+)%)"
        if api then
            export[#export+1] = api
        end
    end
    for line in io.lines(folder.."/lualib.h") do
        local api = line:match "^%s*LUALIB_API[%w%s%*_]+%(([%w_]+)%)"
        if api then
            export[#export+1] = api
        end
    end
    table.sort(export)
    if version then
        return version // 100 * 10 + version % 10, export
    end
    if version_major and version_minor then
        return version_major * 10 + version_minor, export
    end
    return 0, export
end

return function (path)
    local output = path.."/lua.def"
    if fs.exists(output) then
        return
    end
    local version, export = parse(path)
    local s = {}
    s[#s+1] = ([[LIBRARY lua%s]]):format(version)
    s[#s+1] = [[EXPORTS]]
    for _, api in ipairs(export) do
        s[#s+1] = ([[    %s]]):format(api)
    end
    local f <close> = assert(io.open(output, "w"))
    f:write(table.concat(s, "\n"))
end
