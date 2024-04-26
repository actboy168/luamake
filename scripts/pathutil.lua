local fsutil = require "fsutil"

local mt = {}

local function create_internal(path)
    return setmetatable({ value = path }, mt)
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

local function create(workdir, path)
    if type(path) == "userdata" then
        path = tostring(path)
    else
        path = path_normalize(workdir, path)
    end
    return create_internal(path)
end

local function tostr(base, path)
    if is(path) then
        return path.value
    end
    return path_normalize(base, path)
end

local function tovalue(path)
    if is(path) then
        return true, path.value
    end
    return false, tostring(path)
end

function mt.__concat(lft, rht)
    if type(lft) == "string" then
        local path = lft..rht.value
        return create_internal(path)
    else
        local path = lft.value..rht
        return create_internal(path)
    end
end

return {
    create = create,
    tostr = tostr,
    tovalue = tovalue,
}
