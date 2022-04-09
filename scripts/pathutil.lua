local fs = require "bee.filesystem"
local fsutil = require "fsutil"

local mt = {}

local function create(path)
    return setmetatable({
        value = path,
        accepted = false,
    }, mt)
end

local function path_normalize(base, path)
    if path:sub(1, 1) ~= "$" and not fs.path(path):is_absolute() then
        path = fsutil.relative(fsutil.join(base, path), WORKDIR)
    end
    return path:gsub('\\', '/')
end

local function accept(base, path)
    if mt == getmetatable(path) then
        if not path.accepted then
            path.value = path_normalize(base, path.value)
            path.accepted = true
        end
    end
    return path
end

local function normalize(base, path)
    if mt == getmetatable(path) then
        if not path.accepted then
            path.value = path_normalize(base, path.value)
            path.accepted = true
        end
    else
        path = path_normalize(base, path)
    end
    return path
end

function mt:__tostring()
    assert(self.accepted, "Cannot be used before accept.")
    return self.value
end

function mt:__concat(rhs)
    local path = self.value .. rhs
    return create(path)
end

function mt:__div(rhs)
    local path = fsutil.join(self.value, rhs)
    return create(path)
end

return {
    create = create,
    normalize = normalize,
    accept = accept,
}
