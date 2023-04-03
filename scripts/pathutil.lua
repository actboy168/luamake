local fsutil = require "fsutil"

local mt = {}

local function create(path, accepted)
    return setmetatable({
        value = path,
        accepted = accepted,
    }, mt)
end

local function path_normalize(base, path)
    path = tostring(path)
    if path:sub(1, 1) ~= "$" then
        if not fsutil.is_absolute(path) then
            path = fsutil.join(base, path)
            path = fsutil.relative(path, WORKDIR)
        end
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

local function tostring(base, path)
    if mt == getmetatable(path) then
        if not path.accepted then
            path.value = path_normalize(base, path.value)
            path.accepted = true
        end
        return path.value
    end
    return path_normalize(base, path)
end

local function is(path)
    return mt == getmetatable(path)
end

function mt:__tostring()
    assert(self.accepted, "Cannot be used before accept.")
    return self.value
end

function mt:__concat(rhs)
    local path = self.value..rhs
    return create(path, self.accepted)
end

function mt:__div(rhs)
    local path = fsutil.join(self.value, rhs)
    return create(path, self.accepted)
end

return {
    create = create,
    tostring = tostring,
    accept = accept,
    is = is,
}
