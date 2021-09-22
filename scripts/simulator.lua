local writer = require 'writer'
local sandbox = require "sandbox"
local fs = require 'bee.filesystem'
local fsutil = require 'fsutil'
local arguments = require "arguments"
local globals = require "globals"

local mainSimulator = {}

function mainSimulator:source_set(name)
    assert(type(name) == "string", "Name is not a string.")
    return function (attribute)
        writer:add_target { 'source_set', name, attribute, self }
    end
end
function mainSimulator:shared_library(name)
    assert(type(name) == "string", "Name is not a string.")
    return function (attribute)
        writer:add_target { 'shared_library', name, attribute, self }
    end
end
function mainSimulator:static_library(name)
    assert(type(name) == "string", "Name is not a string.")
    return function (attribute)
        writer:add_target { 'static_library', name, attribute, self }
    end
end
function mainSimulator:executable(name)
    assert(type(name) == "string", "Name is not a string.")
    return function (attribute)
        writer:add_target { 'executable', name, attribute, self }
    end
end
function mainSimulator:lua_library(name)
    assert(type(name) == "string", "Name is not a string.")
    return function (attribute)
        writer:add_target { 'lua_library', name, attribute, self }
    end
end
function mainSimulator:build(name)
    if type(name) == "table" then
        writer:add_target { 'build', nil, name, self }
        return
    end
    assert(type(name) == "string", "Name is not a string.")
    return function (attribute)
        writer:add_target { 'build', name, attribute, self }
    end
end
function mainSimulator:copy(name)
    if type(name) == "table" then
        writer:add_target { 'copy', nil, name, self }
        return
    end
    assert(type(name) == "string", "Name is not a string.")
    return function (attribute)
        writer:add_target { 'copy', name, attribute, self }
    end
end
function mainSimulator:default(attribute)
    if self == mainSimulator then
        writer:add_target {'default', attribute}
    end
end
function mainSimulator:phony(name)
    if type(name) == "table" then
        writer:add_target { 'phony', nil, name, self }
        return
    end
    assert(type(name) == "string", "Name is not a string.")
    return function (attribute)
        writer:add_target { 'phony', name, attribute, self }
    end
end
function mainSimulator:variable(name, value)
    assert(type(name) == "string", "Name is not a string.")
    writer:add_target { 'variable', name, value }
end

local alias = {
    exe = "executable",
    dll = "shared_library",
    lib = "static_library",
    src = "source_set",
    lua_dll = "lua_library",
}
for to, from in pairs(alias) do
    mainSimulator[to] = mainSimulator[from]
end

local mainMt = {}
mainMt.__index = globals
function mainMt:__newindex(k, v)
    if arguments.args[k] ~= nil then
        return
    end
    globals[k] = v
end
function mainMt:__pairs()
    return pairs(globals)
end

do
    setmetatable(mainSimulator, mainMt)
end

local function createSubSimulator(parentSimulator)
    local subMt = {}
    subMt.__index = parentSimulator
    function subMt:__newindex(k, v)
        if arguments.args[k] ~= nil then
            return
        end
        rawset(self, k, v)
    end
    function subMt:__pairs()
        local selfpairs = true
        local mark = {}
        local pnext, parent = pairs(parentSimulator)
        return function (_, k)
            if selfpairs then
                local newk, newv = next(self, k)
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
                newk, newv = pnext(parent, newk)
            until newk == nil or not mark[newk]
            return newk, newv
        end, self
    end
    return setmetatable({}, subMt)
end

local function openfile(name, mode)
    local f, err = io.open(name, mode)
    if f and (mode == nil or mode:match "r") then
        writer:add_script(name)
    end
    return f, err
end

local visited = {}

local function isVisited(rootdir, filename)
    local path = fsutil.normalize(rootdir, filename)
    if visited[path] then
        return true
    end
    visited[path] = true
end

local function importfile(simulator, rootdir, filename)
    if isVisited(rootdir, filename) then
        return
    end
    simulator.workdir = rootdir
    sandbox {
        rootdir = rootdir,
        builddir = globals.builddir,
        preload =  {
            luamake = simulator,
            msvc = (not arguments.args.prebuilt and globals.compiler == 'msvc') and require "msvc" or nil
        },
        openfile = openfile,
        main = filename,
        args = arg,
    }
end

function mainSimulator:import(path)
    local absolutepath = fsutil.normalize(self.workdir, path)
    local rootdir = fsutil.parent_path(absolutepath)
    local filename = fsutil.filename(absolutepath)
    importfile(createSubSimulator(self), rootdir, filename)
end

local function import(path)
    importfile(mainSimulator, WORKDIR:string(), path or "make.lua")
end

local function generate(force)
    writer:generate(force)
end

return  {
    import = import,
    generate = generate,
}
