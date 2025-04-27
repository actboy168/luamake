local fs = require "bee.filesystem"
local sp = require "bee.subprocess"
local fsutil = require "fsutil"
local globals = require "globals"
local arguments = require "arguments"
local log = require "log"
local os_arch = require "os_arch"

local ProgramFiles = os_arch ~= "x86" and "ProgramFiles(x86)" or "ProgramFiles"
local vswhere = os.getenv(ProgramFiles).."/Microsoft Visual Studio/Installer/vswhere.exe"
local need = { LIB = true, LIBPATH = true, PATH = true, INCLUDE = true }

local function writeall(filename, content)
    local f <close> = assert(io.open(filename, "w"))
    if content then
        f:write(content)
    end
end

local function readall(filename)
    local f <close> = assert(io.open(filename, "r"))
    return f:read "a"
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
        "-nologo",
        "-latest",
        "-prerelease",
        "-utf8",
        "-products", "*",
        "-property", "installationPath",
        stdout = true,
        stderr = "stdout",
    })
    local result = strtrim(process.stdout:read "a")
    process.stdout:close()
    if process:wait() ~= 0 then
        log.fastfail("[vswhere] %s", result)
    end
    if result == "" then
        log.fastfail("[vswhere] VisualStudio not found. %s", result)
    end
    InstallDir = result
    return InstallDir
end

local function parse_env(str)
    local pos = str:find("=")
    if not pos then
        return
    end
    return strtrim(str:sub(1, pos - 1)), strtrim(str:sub(pos + 1))
end

local function find_winsdk()
    local function query(command)
        local f = io.popen(command, "r")
        if f then
            for l in f:lines() do
                local r = l:match "^    [^%s]+    [^%s]+    (.*)$"
                if r then
                    f:close()
                    return r
                end
            end
        end
    end
    local function find(dir)
        local max
        for file in fs.pairs(dir.."/include") do
            if fs.exists(file / "um" / "winsdkver.h") then
                local version = file:filename():string()
                if version:sub(1, 3) == "10." then
                    if max then
                        if max < version then
                            max = version
                        end
                    else
                        max = version
                    end
                end
            end
        end
        return max
    end
    for _, v in ipairs {
        [[HKLM\SOFTWARE\Wow6432Node]],
        [[HKCU\SOFTWARE\Wow6432Node]],
        [[HKLM\SOFTWARE]],
        [[HKCU\SOFTWARE]]
    } do
        local WindowsSdkDir = query(([[reg query "%s\Microsoft\Microsoft SDKs\Windows\v10.0" /v "InstallationFolder"]]):format(v))
        if WindowsSdkDir then
            local WindowSdkVersion = find(WindowsSdkDir)
            if WindowSdkVersion then
                return WindowSdkVersion
            end
        end
    end
end

local function find_toolset()
    local verfile = installpath().."/VC/Auxiliary/Build/Microsoft.VCToolsVersion.default.txt"
    local raw = readall(verfile)
    local res = strtrim(raw)
    assert(res, ("`%s` parse failed."):format(raw))
    return res
end

local function vsdevcmd(arch, winsdk, toolset, f)
    local vsvars32 = installpath().."/Common7/Tools/VsDevCmd.bat"
    local args = { vsvars32 }
    if arch then
        args[#args+1] = ("-arch=%s"):format(arch)
    end
    if winsdk then
        args[#args+1] = ("-winsdk=%s"):format(winsdk)
    end
    if toolset then
        args[#args+1] = ("-vcvars_ver=%s"):format(toolset)
    end
    local process = assert(sp.spawn {
        args, "&&", "set",
        stderr = true,
        stdout = true,
        searchPath = true,
        env = {
            VSCMD_SKIP_SENDTELEMETRY = "1"
        }
    })
    for line in process.stdout:lines() do
        local name, value = parse_env(line)
        if name and value then
            f(name, value)
        end
    end
    local err = process.stderr:read "a"
    process.stdout:close()
    process.stderr:close()
    if process:wait() ~= 0 then
        log.fastfail("Call `VsDevCmd.bat` error:\n%s", err)
    end
end

local function environment(arch, winsdk, toolset)
    local env = {}
    vsdevcmd(arch, winsdk, toolset, function (name, value)
        name = name:upper()
        if need[name] then
            env[name] = value
        end
    end)
    return env
end

local function getMsvcDepsPrefix(env)
    local testdir = os.tmpname()
    fs.create_directories(testdir)
    writeall(testdir.."/test.c", "#include <stddef.h>")
    writeall(testdir.."/build.ninja", [[
rule showIncludes
  command = cl /nologo /showIncludes -c $in
build test: showIncludes test.c
]])
    local process = assert(sp.spawn {
        "cmd", "/c", "ninja",
        searchPath = true,
        env = env,
        cwd = testdir,
        stdout = true,
        stderr = "stdout",
    })
    local data = process.stdout:read "a"
    if process:wait() ~= 0 then
        log.fastfail("ninja failed: %s", data)
    end
    fs.remove_all(testdir)

    for line in data:gmatch "[^\n\r]+" do
        local m = line:match("[^:]+:[^:]+:")
        if m then
            return m
        end
    end
    log.fastfail("parse msvc_deps_prefix failed:\n%s", data)
end

local function toolspath(toolset)
    return installpath().."/VC/Tools/MSVC/"..toolset
end

local function binpath(arch, toolset)
    local host
    if os_arch == "x86_64" then
        host = "Hostx64"
    elseif os_arch == "x86" then
        host = "Hostx86"
    elseif os_arch == "arm64" then
        host = "Hostx64"
    else
        error("Cannot detect architecture")
    end
    return toolspath(toolset).."/bin/"..host.."/"..arch
end

local function vcrtpath(arch, optimize, toolset)
    local RedistVersion = (function ()
        local verfile = installpath().."/VC/Auxiliary/Build/Microsoft.VCRedistVersion.default.txt"
        local r = readall(verfile)
        return strtrim(r)
    end)()
    local ToolsetVersion = (function ()
        local verfile = toolspath(toolset).."/include/yvals_core.h"
        local r = readall(verfile)
        return r:match "#define%s+_MSVC_STL_VERSION%s+(%d+)"
    end)()
    local path = installpath().."/VC/Redist/MSVC/"..RedistVersion
    if optimize == "off" then
        return path.."/debug_nonredist/"..arch.."/Microsoft.VC"..ToolsetVersion..".DebugCRT"
    end
    return path.."/"..arch.."/Microsoft.VC"..ToolsetVersion..".CRT"
end

local function ucrtpath(arch, optimize)
    local UniversalCRTSdkDir
    vsdevcmd(arch, find_winsdk(), find_toolset(), function (name, value)
        if name == "UniversalCRTSdkDir" then
            UniversalCRTSdkDir = value
        end
    end)
    if not UniversalCRTSdkDir then
        return
    end
    local path = UniversalCRTSdkDir.."/Redist"
    local redist, ver
    local function accept(p, version)
        local ucrt = p.."/ucrt/DLLs/"..arch
        if fs.exists(ucrt) then
            if not ver or ver < version then
                redist, ver = ucrt, version
            end
        end
    end
    accept(path, 0)
    for p in fs.pairs(path) do
        local version = p:filename():string():gsub("10%.0%.([0-9]+)%.0", "%1")
        version = tonumber(version)
        accept(p:string(), version)
    end
    if not redist then
        return
    end
    if optimize == "off" then
        if ver == 0 then
            --TODO 不一定合理，但至少比0好
            ver = 17134
        end
        return redist, UniversalCRTSdkDir.."/bin/10.0."..ver..".0/"..arch.."/ucrt"
    end
    return redist
end

local function llvmpath()
    local path = installpath().."/VC/Tools/Llvm/x64/lib/clang/"
    for p in fs.pairs(path) do
        local version = p:filename():string()
        return path..version.."/lib/windows/"
    end
end

local m = {}
local env
local msvc_deps_prefix

local ArchAlias = {
    x86_64 = "x64",
    x86 = "x86",
}

local function getConsoleCP()
    local f = io.popen("chcp", "r")
    if f then
        local data = f:read "a"
        return data:match "%d+"
    end
end

local function readEnvConfig()
    local EnvConfig = fsutil.join(WORKDIR, globals.builddir, "env.lua")
    local f <close> = assert(io.open(EnvConfig, "r"))
    local data = assert(f:read "a")
    local config = assert(load(data, "t", nil))()
    f:close()
    return config
end

local function writeEnvConfig(data)
    local builddir = fsutil.join(WORKDIR, globals.builddir)
    fs.create_directories(builddir)
    local EnvConfig = fsutil.join(builddir, "env.lua")
    local f <close> = assert(io.open(EnvConfig, "w"))
    f:write(data)
end

local function updateEnvConfig()
    if not env then
        local config = readEnvConfig()
        env = config.env
        msvc_deps_prefix = config.prefix
    end
end

function m.hasEnvConfig()
    local EnvConfig = fsutil.join(WORKDIR, globals.builddir, "env.lua")
    return fs.exists(EnvConfig)
end

function m.cleanEnvConfig()
    local EnvConfig = fsutil.join(WORKDIR, globals.builddir, "env.lua")
    fs.remove(EnvConfig)
end

function m.createEnvConfig(arch, rebuild)
    local console_cp = getConsoleCP()
    if not rebuild and m.hasEnvConfig() then
        local config = readEnvConfig()
        if config.arch == arch
            and (not console_cp or config.console_cp == console_cp)
            and config.toolset and fs.exists(toolspath(config.toolset))
        then
            env = config.env
            msvc_deps_prefix = config.prefix
            globals.winsdk = config.winsdk
            globals.toolset = config.toolset
            return
        end
    end
    local winsdk = find_winsdk()
    local toolset = find_toolset()
    globals.winsdk = winsdk
    globals.toolset = toolset
    env = environment(ArchAlias[arch], winsdk, toolset)
    msvc_deps_prefix = getMsvcDepsPrefix(env)

    local s = {}
    s[#s+1] = "return {"
    s[#s+1] = ("console_cp=%q,"):format(console_cp)
    s[#s+1] = ("arch=%q,"):format(arch)
    if winsdk then
        s[#s+1] = ("winsdk=%q,"):format(winsdk)
    end
    s[#s+1] = ("toolset=%q,"):format(toolset)
    s[#s+1] = ("prefix=%q,"):format(msvc_deps_prefix)
    s[#s+1] = "env={"
    for name, value in pairs(env) do
        s[#s+1] = ("%s=%q,"):format(name, value)
    end
    s[#s+1] = "},"
    s[#s+1] = "}"
    s[#s+1] = ""
    writeEnvConfig(table.concat(s, "\n"))
end

function m.getEnv()
    updateEnvConfig()
    return env
end

function m.getPrefix()
    updateEnvConfig()
    return msvc_deps_prefix
end

function m.archAlias(arch)
    return ArchAlias[arch]
end

m.binpath = binpath
m.vcrtpath = vcrtpath
m.ucrtpath = ucrtpath
m.llvmpath = llvmpath

m.createEnvConfig(globals.arch, arguments.what == "rebuild")

return m
