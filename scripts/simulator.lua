local lm = require 'luamake'
local sandbox = require "sandbox"
local fs = require 'bee.filesystem'
local arguments = require "arguments"

local dofile

local globals = {}
for k, v in pairs(arguments) do
    globals[k] = v
end

local targets = {}
local function accept(type, name, attribute)
    attribute.workdir = attribute.workdir or globals.workdir or "."
    attribute.rootdir = attribute.rootdir or globals.rootdir or "."
    targets[#targets+1] = {type, name, attribute, globals}
end

local simulator = {}

function simulator:source_set(name)
    assert(type(name) == "string", "Name is not a string.")
    return function (attribute)
        accept('source_set', name, attribute)
    end
end
function simulator:shared_library(name)
    assert(type(name) == "string", "Name is not a string.")
    return function (attribute)
        accept('shared_library', name, attribute)
    end
end
function simulator:static_library(name)
    assert(type(name) == "string", "Name is not a string.")
    return function (attribute)
        accept('static_library', name, attribute)
    end
end
function simulator:executable(name)
    assert(type(name) == "string", "Name is not a string.")
    return function (attribute)
        accept('executable', name, attribute)
    end
end
function simulator:lua_library(name)
    assert(type(name) == "string", "Name is not a string.")
    return function (attribute)
        accept('lua_library', name, attribute)
    end
end
function simulator:build(name)
    assert(type(name) == "string", "Name is not a string.")
    return function (attribute)
        accept('build', name, attribute)
    end
end
function simulator:default(attribute)
    accept('default', nil, attribute)
end
function simulator:phony(attribute)
    accept('phony', nil, attribute)
end
function simulator:import(path)
    local filepath = fs.path(path)
    dofile(nil, filepath:parent_path():string(), filepath:filename():string())
end

local alias = {
    exe = "executable",
    dll = "shared_library",
    lib = "static_library",
    src = "source_set",
    lua_dll = "lua_library",
}
for to, from in pairs(alias) do
    simulator[to] = simulator[from]
end

local function setter(_, k, v)
    if arguments._force[k] ~= nil then
        return
    end
    globals[k] = v
end
local function getter(_, k)
    return globals[k]
end
simulator = setmetatable(simulator, {__index = getter, __newindex = setter})

lm._export_targets = targets
lm._export_globals = globals

local function filehook(name, mode)
    local f, err = io.open(name, mode)
    if f then
        lm:add_script(name)
    end
    return f, err
end

function dofile(_, dir, file)
    local last = globals.workdir
    globals.workdir = dir
    assert(sandbox(dir, file, filehook, { luamake = simulator }))(table.unpack(arg))
    globals.workdir = last
end

local function finish()
    lm:finish()
end

return  {
    dofile = dofile,
    finish = finish,
}
