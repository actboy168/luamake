require 'bee'
local sp = require 'bee.subprocess'
local fs = require 'bee.filesystem'
local vswhere = fs.path(os.getenv('ProgramFiles(x86)')) / 'Microsoft Visual Studio' / 'Installer' / 'vswhere.exe'
local need = { LIB = true, LIBPATH = true, PATH = true, INCLUDE = true }

local function createfile(filename, content)
    local f = assert(io.open(filename:string(), 'w'))
    if content then
        f:write(content)
    end
    f:close()
end

local function strtrim(str)
    return str:gsub("^%s*(.-)%s*$", "%1")
end

local function get_path()
    local process = assert(sp.spawn {
        vswhere,
        '-latest',
        '-products', '*',
        '-requires', 'Microsoft.VisualStudio.Component.VC.Tools.x86.x64',
        '-property', 'installationPath',
        stdout = true,
    })
    local result = strtrim(process.stdout:read 'a')
    process.stdout:close()
    process:wait()
    return fs.path(result)
end

local function parse_env(str)
    local pos = str:find('=')
    if not pos then
        return
    end
    return strtrim(str:sub(1, pos - 1)), strtrim(str:sub(pos + 1))
end

local function get_env(self, path, arch, winsdk)
    local env = {}
    local vsvars32 = path / 'Common7' / 'Tools' / 'VsDevCmd.bat'
    local args = { vsvars32:string() }
    if arch then
        args[#args+1] = ('-arch=%s'):format(arch)
    end
    if winsdk then
        args[#args+1] = ('-winsdk=%s'):format(winsdk)
    end
    local process = assert(sp.spawn {
        'cmd', '/c', args, '&', 'set',
        stderr = true,
        stdout = true,
        searchPath = true,
    })
    for line in process.stdout:lines() do
        local name, value = parse_env(line)
        if name and value then
            name = name:upper()
            if need[name] then
                env[name] = value
            end
        end
    end
    process.stdout:close()
    process.stderr:close()
    process:wait()
    return env
end

local function get_prefix(env)
    local testdir = MAKEDIR / 'luamake-temp'
    fs.create_directories(testdir)
    createfile(testdir / 'test.h')
    createfile(testdir / 'test.c', '#include "test.h"')
    local process = assert(sp.shell {
        'cl', '/showIncludes', '/nologo', '-c', 'test.c',
        env = env,
        cwd = testdir,
        stdout = true,
        stderr = true,
    })
    local prefix
    for line in process.stdout:lines() do
        local m = line:match('[^:]+:[^:]+:')
        if m then
            prefix = m
            break
        end
    end
    process.stdout:close()
    process.stderr:close()
    process:wait()
    fs.remove_all(testdir)
    return prefix
end

local m = {}

function m:init(arch, winsdk)
    local path = get_path()
    self.env = get_env(self, path, arch, winsdk)

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
            io.open((WORKDIR / 'build' / 'env.luamake'):string(), 'w')
        ):write(table.concat(env, '\n'))
    ):close()
end

local function init_from_cache(self)
    local f = assert(io.open((WORKDIR / 'build' / 'env.luamake'):string(), 'r'))
    local env = assert(load(assert(f:read 'a')))()
    f:close()

    local path = get_path()
    self.env = get_env(self, path, env.arch, env.winsdk)
end

return setmetatable(m, { __index = function(self, k)
    if k == 'env' then
        init_from_cache(self)
        return self.env
    elseif k == 'prefix' then
        self.prefix = get_prefix(self.env)
        return self.prefix
    end
end})
