local fsutil = require "fsutil"

local mt = {}

local function create_internal(path, accepted)
    return setmetatable({
        value = path,
        accepted = accepted,
    }, mt)
end

local function create(path)
    if type(path) == "userdata" then
        return create_internal(tostring(path), true)
    end
    return create_internal(path, nil)
end

local function path_normalize(base, path)
    path = tostring(path)
    if path:sub(1, 1) ~= "$" then
        if not fsutil.is_absolute(path) then
            path = fsutil.normalize(base, path)
            path = fsutil.relative(path, WORKDIR)
        end
    end
    return path:gsub("\\", "/")
end

local function is(path)
    return mt == getmetatable(path)
end

local function accept(base, path)
    if is(path) then
        if not path.accepted then
            path.value = path_normalize(base, path.value)
            path.accepted = true
        end
    end
    return path
end

local function tostr(base, path)
    if is(path) then
        assert(path.accepted, "Cannot be used before accept.")
        return path.value
    end
    return path_normalize(base, path)
end

local function tovalue(path)
    if is(path) then
        assert(path.accepted, "Cannot be used before accept.")
        return true, path.value
    end
    return false, tostring(path)
end

function mt.__concat(lft, rhs)
    if type(lft) == "string" then
        local path = lft..rhs.value
        return create_internal(path, rhs.accepted)
    else
        local path = lft.value..rhs
        return create_internal(path, lft.accepted)
    end
end

function mt:__div(rhs)
    local path = fsutil.join(self.value, rhs)
    return create_internal(path, self.accepted)
end

return {
    create = create,
    tostr = tostr,
    tovalue = tovalue,
    accept = accept,
}
