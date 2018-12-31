local fs = require "bee.filesystem"

local name = ARGUMENTS["name"] or "lua54.dll"
local input = ARGUMENTS["in"] and fs.path(ARGUMENTS["in"]) or MAKEDIR / "tools" / "lua54"
local output = ARGUMENTS["out"] and fs.path(ARGUMENTS["out"]) or input / "windeps" / "lua54.def"

local export = {}

for line in io.lines((input / "lua.h"):string()) do
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
