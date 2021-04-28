local msvc = require 'msvc'
local fs = require "bee.filesystem"

local m = {}
local env
local prefix
local EnvConfig = WORKDIR / 'build' / 'msvc' / 'env.config'

local function readEnvConfig()
    local f = assert(io.open(EnvConfig:string(), 'r'))
    local config = assert(load(assert(f:read 'a')))()
    f:close()
    return config
end

local function updateEnvConfig()
    local config = readEnvConfig()
    env = config.env
    prefix = config.prefix
end

function m.createEnvConfig(arch, winsdk)
    if fs.exists(EnvConfig) then
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
    assert(
        assert(
            io.open(EnvConfig:string(), 'w')
        ):write(table.concat(s, '\n'))
    ):close()
end

function m.cleanEnvConfig()
    fs.remove(EnvConfig)
end

function m.getenv()
    updateEnvConfig()
    return env
end

function m.getprefix()
    updateEnvConfig()
    return prefix
end

return m
