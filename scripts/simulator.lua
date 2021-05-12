local lm = require 'luamake'
local sandbox = require "sandbox"
local fs = require 'bee.filesystem'
local arguments = require "arguments"
local globals = require "globals"

local dofile

local targets = {}
local simulator = {}
local mainscript = true

local function accept(type, name, attribute)
    attribute.workdir = attribute.workdir or globals.workdir or "."
    attribute.rootdir = attribute.rootdir or globals.rootdir or "."
    targets[#targets+1] = {type, name, attribute}
end

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
    if type(name) == "table" then
        accept('build', nil, name)
        return
    end
    assert(type(name) == "string", "Name is not a string.")
    return function (attribute)
        accept('build', name, attribute)
    end
end
function simulator:shell(name)
    if type(name) == "table" then
        accept('shell', nil, name)
        return
    end
    assert(type(name) == "string", "Name is not a string.")
    return function (attribute)
        accept('shell', name, attribute)
    end
end
function simulator:copy(name)
    if type(name) == "table" then
        accept('copy', nil, name)
        return
    end
    assert(type(name) == "string", "Name is not a string.")
    return function (attribute)
        accept('copy', name, attribute)
    end
end
function simulator:default(attribute)
    if mainscript then
        targets[#targets+1] = {'default', attribute}
    end
end
function simulator:phony(name)
    if type(name) == "table" then
        accept('phony', nil, name)
        return
    end
    assert(type(name) == "string", "Name is not a string.")
    return function (attribute)
        accept('phony', name, attribute)
    end
end
function simulator:import(path, env)
    local v = mainscript
    mainscript = false
    dofile(nil, fs.path(path), env)
    mainscript = v
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
    if arguments.args[k] ~= nil then
        return
    end
    globals[k] = v
end
local function getter(_, k)
    return globals[k]
end
simulator = setmetatable(simulator, {__index = getter, __newindex = setter})

lm._export_targets = targets

local function filehook(name, mode)
    local f, err = io.open(name, mode)
    if f then
        lm:add_script(name)
    end
    return f, err
end

local visited = {}
local function isVisited(path)
    path = path:string()
    if visited[path] then
        return true
    end
    visited[path] = true
end
function dofile(_, path, env)
    path = fs.absolute(path, fs.path(globals.workdir or "."))
    if isVisited(path) then
        return
    end
    local dir = path:parent_path():string()
    local file = path:filename():string()
    local last = globals.workdir
    globals.workdir = dir
    assert(sandbox {
        root = dir,
        main = file,
        io_open = filehook,
        preload =  {
            luamake = simulator,
            msvc = (not arguments.args.prebuilt and globals.compiler == 'msvc') and require "msvc" or nil
        },
        env = env,
        builddir = globals.builddir,
    })(table.unpack(arg))
    globals.workdir = last
end

local function finish()
    lm:finish()
end

return  {
    dofile = dofile,
    finish = finish,
}
