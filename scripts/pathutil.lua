local fsutil = require "fsutil"
local fs = require "bee.filesystem"

local function path_normalize(base, path)
    if path:sub(1, 1) ~= "$" then
        if not fsutil.is_absolute(path) then
            path = fsutil.normalize(base, path)
            path = fsutil.relative(path, WORKDIR)
        end
    end
    return path:gsub("\\", "/")
end

local function is(path)
    return type(path) == "userdata"
end

local function create(workdir, path)
    return fs.path(path_normalize(workdir, path))
end

local function tostr(base, path)
    if is(path) then
        return tostring(path)
    else
        return path_normalize(base, path)
    end
end

local function tovalue(path)
    return is(path), tostring(path)
end

return {
    create = create,
    tostr = tostr,
    tovalue = tovalue,
}
