local command = require "command"

local lst = {}
for name in pairs(command.list()) do
    lst[#lst+1] = name
end
table.sort(lst)

for _, name in ipairs(lst) do
    print("\tluamake "..name)
end
