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

local InstallDir
local function installpath()
    if InstallDir then
        return InstallDir
    end
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
    assert(result ~= "", "can't find msvc.")
    InstallDir = fs.path(result)
    return InstallDir
end

local function parse_env(str)
    local pos = str:find('=')
    if not pos then
        return
    end
    return strtrim(str:sub(1, pos - 1)), strtrim(str:sub(pos + 1))
end

local function environment(arch, winsdk)
    local env = {}
    local vsvars32 = installpath() / 'Common7' / 'Tools' / 'VsDevCmd.bat'
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

local function prefix(env)
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
    assert(prefix, "can't find msvc.")
    return prefix
end

local function crtpath(platform)
    local RedistVersion = (function ()
        local verfile = installpath() / 'VC' / 'Auxiliary' / 'Build' / 'Microsoft.VCRedistVersion.default.txt'
        local f = assert(io.open(verfile:string(), 'r'))
        local r = f:read 'a'
        f:close()
        return strtrim(r)
    end)()
    return installpath() / 'VC' / 'Redist' / 'MSVC' / RedistVersion / platform / 'Microsoft.VC141.CRT'
end

local function ucrtpath(platform)
    local registry = require 'bee.registry'
    local reg = registry.open [[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows Kits\Installed Roots]]
    local path = fs.path(reg.KitsRoot10)
    return path / 'Redist' / 'ucrt' / 'DLLs' / platform
end

return {
    installpath = installpath,
    environment = environment,
    prefix = prefix,
    crtpath = crtpath,
    ucrtpath = ucrtpath,
}
