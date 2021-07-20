local fs = require 'bee.filesystem'
local platform = require 'bee.platform'

local fsutil = {}

function fsutil.normalize(p)
    local pattern = platform.OS == "Windows" and '[^/\\]*' or '[^/]*'
    local stack = {}
    p:string():gsub(pattern, function (w)
        if #w == 0 and #stack ~= 0 then
        elseif w == '..' and #stack ~= 0 and stack[#stack] ~= '..' then
            stack[#stack] = nil
        elseif w ~= '.' then
            stack[#stack + 1] = w
        end
    end)
    return fs.path(table.concat(stack, '/'))
end

function fsutil.absolute(path, base)
    return fsutil.normalize(base / path)
end

return fsutil
