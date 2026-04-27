local fsutil = require "fsutil"

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
    return type(path) == "userdata" or (type(path) == "table" and path.__path)
end

local path_mt
path_mt = {
    __div = function(a, b)
        local p = fsutil.join(tostring(a), tostring(b))
        return setmetatable({ __path = p }, path_mt)
    end,
    __tostring = function(self)
        return self.__path
    end,
    __len = function(self)
        return #self.__path
    end,
    __index = function(self, key)
        local s = self.__path
        if key == "string" then
            return function() return s end
        end
        if key == "filename" then
            return function() return fsutil.filename(s) end
        end
        if key == "parent_path" then
            return function() return fsutil.parent_path(s) end
        end
        if key == "extension" then
            return function() return fsutil.extension(s) end
        end
        if key == "stem" then
            return function() return fsutil.stem(s) end
        end
        if key == "is_absolute" then
            return function() return fsutil.is_absolute(s) end
        end
        if key == "is_relative" then
            return function() return not fsutil.is_absolute(s) end
        end
        if key == "lexically_normal" then
            return function() return fsutil.normalize(s) end
        end
        return nil
    end,
}

local function create(workdir, path)
    local p = path_normalize(workdir, path)
    return setmetatable({ __path = p }, path_mt)
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
