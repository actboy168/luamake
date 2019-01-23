local msvc = require 'msvc_helper'

local m = {}

function m:create_config(arch, winsdk)
    local env = {}
    env[#env+1] = "return {"
    env[#env+1] = ("arch=%q,"):format(arch)
    if winsdk then
        env[#env+1] = ("winsdk=%q,"):format(winsdk)
    end
    env[#env+1] = "}"
    env[#env+1] = ""
    assert(
        assert(
            io.open((WORKDIR / 'build' / 'msvc' / 'env.luamake'):string(), 'w')
        ):write(table.concat(env, '\n'))
    ):close()
end

function m:init(arch, winsdk)
    local path = msvc.get_path()
    self.env = msvc.get_env(path, arch, winsdk)
end

local function init_from_cache(self)
    local f = assert(io.open((WORKDIR / 'build' / 'msvc' / 'env.luamake'):string(), 'r'))
    local env = assert(load(assert(f:read 'a')))()
    f:close()

    local path = msvc.get_path()
    self.env = msvc.get_env(path, env.arch, env.winsdk)
end

return setmetatable(m, { __index = function(self, k)
    if k == 'env' then
        init_from_cache(self)
        return self.env
    elseif k == 'prefix' then
        self.prefix = msvc.get_prefix(self.env)
        return self.prefix
    end
end})
