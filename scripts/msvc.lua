local msvc = require 'msvc_helper'

local m = {}
local env
local prefix

function m.create_config(arch, winsdk)
    local s = {}
    s[#s+1] = "return {"
    s[#s+1] = ("arch=%q,"):format(arch)
    if winsdk then
        s[#s+1] = ("winsdk=%q,"):format(winsdk)
    end
    s[#s+1] = "}"
    s[#s+1] = ""
    assert(
        assert(
            io.open((WORKDIR / 'build' / 'msvc' / 'env.luamake'):string(), 'w')
        ):write(table.concat(s, '\n'))
    ):close()
    env = nil
    prefix = nil
end

function m.init(arch, winsdk)
    env = msvc.environment(arch, winsdk)
end

function m.getenv()
    if not env then
        local f = assert(io.open((WORKDIR / 'build' / 'msvc' / 'env.luamake'):string(), 'r'))
        local cache = assert(load(assert(f:read 'a')))()
        f:close()
        env = msvc.environment(cache.arch, cache.winsdk)
    end
    return env
end

function m.getprefix()
    if not prefix then
        prefix = msvc.prefix(m.getenv())
    end
    return prefix
end

return m
