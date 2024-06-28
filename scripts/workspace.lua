local arguments = require "arguments"
local pathutil = require "pathutil"
local globals = require "globals"

local AttributePlatform <const> = 0
local AttributePaths <const> = 1
local AttributeArgs <const> = 2
local AttributeStrings <const> = 3
local AttributeGlobs <const> = 4
local AttributePath <const> = 5

local ATTRIBUTE <const> = {
    -- os
    windows     = AttributePlatform,
    linux       = AttributePlatform,
    macos       = AttributePlatform,
    ios         = AttributePlatform,
    android     = AttributePlatform,
    freebsd     = AttributePlatform,
    openbsd     = AttributePlatform,
    netbsd      = AttributePlatform,
    -- cc
    msvc        = AttributePlatform,
    gcc         = AttributePlatform,
    clang       = AttributePlatform,
    clang_cl    = AttributePlatform,
    mingw       = AttributePlatform,
    emcc        = AttributePlatform,
    -- paths
    includes    = AttributePaths,
    sysincludes = AttributePaths,
    linkdirs    = AttributePaths,
    outputs     = AttributePaths,
    -- path
    script      = AttributePath,
    -- strings
    objdeps     = AttributeStrings,
    defines     = AttributeStrings,
    flags       = AttributeStrings,
    ldflags     = AttributeStrings,
    links       = AttributeStrings,
    frameworks  = AttributeStrings,
    deps        = AttributeStrings,
    confs       = AttributeStrings,
    -- globs
    inputs      = AttributeGlobs,
    sources     = AttributeGlobs,
    -- args
    args        = AttributeArgs,
}

local LINK_ATTRIBUTE <const> = {
    ldflags = true,
    links = true,
    linkdirs = true,
    frameworks = true,
}

local function push_globs(t, v)
    local vt = type(v)
    if vt == "string" then
        t[#t+1] = v
    elseif vt == "userdata" then
        t[#t+1] = v
    elseif vt == "table" then
        if getmetatable(v) ~= nil then
            t[#t+1] = v
        else
            for i = 1, #v do
                push_globs(t, v[i])
            end
        end
    end
end

local function push_strings(t, v)
    local vt = type(v)
    if vt == "string" then
        t[#t+1] = v
    elseif vt == "table" then
        for i = 1, #v do
            push_strings(t, v[i])
        end
    end
end

local function path2string(root, v)
    local vt = type(v)
    if vt == "string" then
        return pathutil.tostr(root, v)
    elseif vt == "userdata" then
        return pathutil.tostr(root, v)
    elseif vt == "table" then
        if getmetatable(v) ~= nil then
            return pathutil.tostr(root, v)
        end
    end
end

local function push_paths(t, v, root)
    local vt = type(v)
    if vt == "string" then
        t[#t+1] = pathutil.tostr(root, v)
    elseif vt == "userdata" then
        t[#t+1] = pathutil.tostr(root, v)
    elseif vt == "table" then
        if getmetatable(v) ~= nil then
            t[#t+1] = pathutil.tostr(root, v)
        else
            for i = 1, #v do
                push_paths(t, v[i], root)
            end
        end
    end
end

local function push_mix(t, v, root)
    local vt = type(v)
    if vt == "string" then
        if v:sub(1, 1) == "@" then
            t[#t+1] = pathutil.tostr(root, v:sub(2))
        else
            t[#t+1] = v:gsub("@{([^}]*)}", function (s)
                return pathutil.tostr(root, s)
            end)
        end
    elseif vt == "userdata" then
        t[#t+1] = pathutil.tostr(root, v)
    elseif vt == "table" then
        if getmetatable(v) ~= nil then
            t[#t+1] = pathutil.tostr(root, v)
        else
            for i = 1, #v do
                push_mix(t, v[i], root)
            end
        end
    end
end

local function push_args(t, v, root)
    for i = 1, #v do
        push_mix(t, v[i], root)
    end
end

local function push_table(t, a, NOLINK)
    for k, v in pairs(a) do
        if type(k) ~= "string" then
            goto continue
        end
        if NOLINK and LINK_ATTRIBUTE[k] then
            goto continue
        end
        if ATTRIBUTE[k] == AttributePlatform then
        elseif ATTRIBUTE[k] == AttributePaths or ATTRIBUTE[k] == AttributeArgs or ATTRIBUTE[k] == AttributeStrings then
            t[k] = t[k] or {}
            push_strings(t[k], v)
            if #t[k] == 0 then
                t[k] = nil
            end
        elseif ATTRIBUTE[k] == AttributeGlobs then
            t[k] = t[k] or {}
            push_globs(t[k], v)
            if #t[k] == 0 then
                t[k] = nil
            end
        else
            t[k] = v
        end
        ::continue::
    end
    return t
end

local function push_attributes(t, a, NOLINK)
    push_table(t, a, NOLINK)
    if a[globals.os] then
        push_table(t, a[globals.os], NOLINK)
    end
    if a[globals.compiler] then
        push_table(t, a[globals.compiler], NOLINK)
    end
    if a.mingw and globals.os == "windows" and globals.hostshell == "sh" then
        push_table(t, a.mingw, NOLINK)
    end
    if a.clang_cl and globals.cc == "clang-cl" then
        push_table(t, a.clang_cl, NOLINK)
    end
end

local function resolve_table(t, a, root)
    for k, v in pairs(a) do
        if type(k) ~= "string" then
            goto continue
        end
        if ATTRIBUTE[k] == AttributePlatform then
        elseif ATTRIBUTE[k] == AttributePaths then
            t[k] = t[k] or {}
            push_paths(t[k], v, root)
            if #t[k] == 0 then
                t[k] = nil
            end
        elseif ATTRIBUTE[k] == AttributePath then
            t[k] = path2string(root, v)
        elseif ATTRIBUTE[k] == AttributeArgs then
            t[k] = t[k] or {}
            push_args(t[k], v, root)
            if #t[k] == 0 then
                t[k] = nil
            end
        elseif ATTRIBUTE[k] == AttributeStrings then
            t[k] = t[k] or {}
            push_strings(t[k], v)
            if #t[k] == 0 then
                t[k] = nil
            end
        elseif ATTRIBUTE[k] == AttributeGlobs then
            t[k] = t[k] or {}
            push_globs(t[k], v)
            if #t[k] == 0 then
                t[k] = nil
            end
        else
            t[k] = v
        end
        ::continue::
    end
    return t
end

local function resolve_attributes(t, a, root)
    resolve_table(t, a, root)
    if a[globals.os] then
        resolve_table(t, a[globals.os], root)
    end
    if a[globals.compiler] then
        resolve_table(t, a[globals.compiler], root)
    end
    if a.mingw and globals.os == "windows" and globals.hostshell == "sh" then
        resolve_table(t, a.mingw, root)
    end
    if a.clang_cl and globals.cc == "clang-cl" then
        resolve_table(t, a.clang_cl, root)
    end
end

local function create(workdir, parent, attri)
    local mt = {}
    function mt:__index(k)
        local v = attri[k]
        if v ~= nil then
            return v
        end
        return parent[k]
    end

    function mt:__newindex(k, v)
        if arguments.args[k] ~= nil then
            return
        end
        if ATTRIBUTE[k] == AttributePaths then
            local t = {}
            push_strings(t, parent[k])
            push_paths(t, v, workdir)
            attri[k] = t
        elseif ATTRIBUTE[k] == AttributeStrings then
            local t = {}
            push_strings(t, parent[k])
            push_strings(t, v)
            attri[k] = t
        else
            attri[k] = v
        end
    end

    function mt:__call(_, new_attri)
        for k, v in pairs(new_attri) do
            if arguments.args[k] == nil then
                if ATTRIBUTE[k] == AttributePaths or ATTRIBUTE[k] == AttributeStrings then
                    if attri[k] == nil then
                        local t = {}
                        push_strings(t, parent[k])
                        push_strings(t, v)
                        attri[k] = t
                    else
                        push_strings(attri[k], v)
                    end
                else
                    attri[k] = v
                end
            end
        end
    end

    if globals == attri then
        function mt:__pairs()
            return function (_, k)
                return next(attri, k)
            end
        end

        return setmetatable({ workdir = workdir }, mt)
    end
    function mt:__pairs()
        local selfpairs = true
        local mark = {}
        local parent_next, parent_state = pairs(parent)
        return function (_, k)
            if selfpairs then
                local newk, newv = next(attri, k)
                if newk ~= nil then
                    mark[newk] = true
                    return newk, newv
                end
                selfpairs = false
                k = nil
            end
            local newk = k
            local newv
            repeat
                newk, newv = parent_next(parent_state, newk)
            until newk == nil or not mark[newk]
            return newk, newv
        end
    end

    return setmetatable({ workdir = workdir }, mt)
end

return {
    create = create,
    push_attributes = push_attributes,
    resolve_attributes = resolve_attributes,
    push_strings = push_strings,
}
