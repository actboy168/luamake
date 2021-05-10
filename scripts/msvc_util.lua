local msvc = require 'msvc'
local fs = require "bee.filesystem"
local globals = require "globals"

local m = {}
local env
local prefix

local function readEnvConfig()
    local EnvConfig = fs.path(globals.builddir) / 'env.config'
    local f = assert(io.open(EnvConfig:string(), 'r'))
    local config = assert(load(assert(f:read 'a')))()
    f:close()
    return config
end

local function writeEnvConfig(data)
    local EnvConfig = fs.path(globals.builddir) / 'env.config'
    assert(
        assert(
            io.open(EnvConfig:string(), 'w')
        ):write(data)
    ):close()
end

local function updateEnvConfig()
    local config = readEnvConfig()
    env = config.env
    prefix = config.prefix
end

function m.hasEnvConfig()
    local EnvConfig = fs.path(globals.builddir) / 'env.config'
    return fs.exists(EnvConfig)
end

function m.cleanEnvConfig()
    local EnvConfig = fs.path(globals.builddir) / 'env.config'
    fs.remove(EnvConfig)
end

function m.createEnvConfig(arch, winsdk)
    if m.hasEnvConfig() then
        local config = readEnvConfig()
        if config.arch == arch and config.winsdk == winsdk then
            env = config.env
            prefix = config.prefix
            return
        end
    end
    env = msvc.environment(arch, winsdk)
    prefix = msvc.prefix(env)

    local s = {}
    s[#s+1] = "return {"
    s[#s+1] = ("arch=%q,"):format(arch)
    if winsdk then
        s[#s+1] = ("winsdk=%q,"):format(winsdk)
    end
    s[#s+1] = ("prefix=%q,"):format(prefix)
    s[#s+1] = ("env={"):format(prefix)
    for name, value in pairs(env) do
        s[#s+1] = ("%s=%q,"):format(name, value)
    end
    s[#s+1] = ("},"):format(prefix)
    s[#s+1] = "}"
    s[#s+1] = ""
    writeEnvConfig(table.concat(s, '\n'))
end

function m.getEnv()
    updateEnvConfig()
    return env
end

function m.getPrefix()
    updateEnvConfig()
    return prefix
end

return m
