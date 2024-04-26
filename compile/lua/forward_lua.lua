local input, output, dllname = ...

local export = {}
for line in io.lines(input.."/lua.h") do
    export[#export+1] = line:match "^%s*LUA_API[%w%s%*_]+%(([%w_]+)%)"
end
for line in io.lines(input.."/lauxlib.h") do
    export[#export+1] = line:match "^%s*LUALIB_API[%w%s%*_]+%(([%w_]+)%)"
end
for line in io.lines(input.."/lualib.h") do
    export[#export+1] = line:match "^%s*LUALIB_API[%w%s%*_]+%(([%w_]+)%)"
end
table.sort(export)

local f <close> = assert(io.open(output, "wb"))
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
