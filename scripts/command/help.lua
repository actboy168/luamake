local fs = require "bee.filesystem"

local lst = {}
for path in fs.pairs(fs.path(package.procdir) / 'scripts' / 'command') do
    if path:equal_extension(".lua") then
        lst[#lst+1] = path:stem():string()
    end
end
table.sort(lst)

for _, name in ipairs(lst) do
    print('\tluamake ' .. name)
end
