local function parse(folder)
    local version
    local export = {}
    for line in io.lines(folder.."/lua.h") do
        local verstr = line:match "^%s*#%s*define%s*LUA_VERSION_NUM%s*([0-9]+)%s*$"
        if verstr then
            version = tostring(tonumber(verstr:sub(1, -3))) .. tostring(tonumber(verstr:sub(-2, -1)))
        end
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
    return version, export
end

local input, output, dllname = ...
local _, export = parse(input)

local f <close> = assert(io.open(output, "w"))
local function writeln(data)
    f:write(data)
    f:write "\n"
end

writeln "// clang-format off"
writeln(([[#define TARGET_NAME %q]]):format(dllname))
writeln [[#if defined(_MSC_VER)]]
writeln [[    #define FORWARDED_EXPORT(exp_name) __pragma (comment (linker, "/export:" #exp_name "=" TARGET_NAME "." #exp_name))]]
writeln [[#elif defined(__GNUC__)]]
writeln [[    #define FORWARDED_EXPORT(exp_name) __asm__ (".section .drectve\n\t.ascii \" -export:" #exp_name "= " TARGET_NAME "." #exp_name " \"");]]
writeln [[#endif]]
writeln [[]]

for _, api in ipairs(export) do
    writeln(([[FORWARDED_EXPORT(%s)]]):format(api))
end
