local writer = require "writer"
local sandbox = require "sandbox"
local fs = require "bee.filesystem"
local fsutil = require "fsutil"
local arguments = require "arguments"
local globals = require "globals"
local pathutil = require "pathutil"

local function create_workspace(workdir, parent, attri)
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
        attri[k] = pathutil.accept(workdir, v)
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

local api = writer.api

local MainWorkspace = create_workspace(globals.workdir, api, globals)

local function openfile(name, mode)
    local f, err = io.open(name, mode)
    if f and (mode == nil or mode:match "r") then
        writer.add_script(name)
    end
    return f, err
end

local visited = {}

local function isVisited(path)
    if visited[path] then
        return true
    end
    visited[path] = true
end

local function importfile(workspace, rootdir, filename)
    sandbox {
        rootdir = rootdir,
        builddir = globals.builddir,
        preload = {
            luamake = workspace,
        },
        openfile = openfile,
        main = filename,
        args = {}
    }
end

function api:import(path)
    local fullpath = pathutil.tostring(self.workdir, path)
    if fs.is_directory(fullpath) then
        fullpath = fsutil.join(fullpath, "make.lua")
    end
    if isVisited(fullpath) then
        return
    end
    local rootdir = fsutil.parent_path(fullpath)
    local filename = fsutil.filename(fullpath)
    local workspace = create_workspace(rootdir, self, {})
    importfile(workspace, rootdir, filename)
end

function api:default(attribute)
    if self == MainWorkspace then
        writer.default(attribute)
    end
end

local function import(path)
    path = path or "make.lua"
    local fullpath = fsutil.absolute(WORKDIR, path)
    if isVisited(fullpath) then
        return
    end
    globals.workdir = WORKDIR
    importfile(MainWorkspace, WORKDIR, path)
end

return {
    import = import,
}
