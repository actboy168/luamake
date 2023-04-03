local fs = require "bee.filesystem"
local fsutil = require "fsutil"

local lst = {}
for path in fs.pairs(fsutil.join(package.procdir, 'scripts', 'command')) do
    if path:equal_extension(".lua") then
        lst[#lst+1] = path:stem():string()
    end
end
table.sort(lst)

for _, name in ipairs(lst) do
    print('\tluamake '..name)
end
