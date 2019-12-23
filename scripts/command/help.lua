local fs = require "bee.filesystem"

local lst = {}
for path in (MAKEDIR / 'scripts' / 'command'):list_directory() do
    if path:equal_extension(".lua") then
        lst[#lst+1] = path:stem():string()
    end
end
table.sort(lst)

for _, name in ipairs(lst) do
    print('\tluamake ' .. name)
end
