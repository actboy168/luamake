local fs = require "bee.filesystem"

local function generator(input, output)
    local export = {}
    local name = input:filename():string() .. ".dll"
    for line in io.lines((input / "lua.h"):string()) do
        local version = line:match "^%s*#%s*define%s*LUA_VERSION_NUM%s*([0-9]+)%s*$"
        if version then
            version = tostring(tonumber(version:sub(1, -3))) .. tostring(tonumber(version:sub(-2, -1)))
            name = ("lua%s.dll"):format(version)
        end
        local api = line:match "^%s*LUA_API[%w%s%*_]+%(([%w_]+)%)"
        if api then
            export[#export+1] = api
        end
    end
    for line in io.lines((input / "lauxlib.h"):string()) do
        local api = line:match "^%s*LUALIB_API[%w%s%*_]+%(([%w_]+)%)"
        if api then
            export[#export+1] = api
        end
    end
    for line in io.lines((input / "lualib.h"):string()) do
        local api = line:match "^%s*LUALIB_API[%w%s%*_]+%(([%w_]+)%)"
        if api then
            export[#export+1] = api
        end
    end
    table.sort(export)
    fs.create_directories(output:parent_path())
    local f = assert(io.open(output:string(), "wb"))
    f:write(("LIBRARY %s\r\n"):format(name))
    f:write("EXPORTS\r\n")
    for _, api in ipairs(export) do
        f:write(("    %s\r\n"):format(api))
    end
    f:close()
end

return function (path)
    if fs.exists(path / "lua.def") then
        return
    end
    generator(path, path / "lua.def")
end
