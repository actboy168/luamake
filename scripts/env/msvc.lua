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

local installationPath
local UniversalCRTSdkDir

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

local function getInstallationPath()
    local process = assert(sp.spawn {
        vswhere,
        "-nologo",
        "-sort",
        "-prerelease",
        "-utf8",
        "-products", "*",
        "-property", "installationPath",
        stdout = true,
        stderr = "stdout",
    })
    local results = {}
    for line in process.stdout:lines() do
        results[#results+1] = strtrim(line)
    end
    process.stdout:close()
    if process:wait() ~= 0 then
        log.fastfail("[vswhere] Error: %s", table.concat(results, "\n"))
    end
    if #results == 0 then
        log.fastfail("[vswhere] VisualStudio not found.")
    end
    return results
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
    local verfile = installationPath.."/VC/Auxiliary/Build/Microsoft.VCToolsVersion.default.txt"
    local raw = readall(verfile)
    local res = strtrim(raw)
    assert(res, ("`%s` parse failed."):format(raw))
    return res
end

local function vsdevcmd(arch, winsdk, toolset)
    local error = { "Call `VsDevCmd.bat` faild." }
    for _, path in ipairs(getInstallationPath()) do
        local env = {}
        local vsvars32 = path.."/Common7/Tools/VsDevCmd.bat"
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
        local err = {}
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
            err[#err+1] = line
            local name, value = parse_env(line)
            if name and value then
                env[name] = value
            end
        end
        err[#err+1] = process.stderr:read "a"
        process.stdout:close()
        process.stderr:close()
        if process:wait() == 0 then
            return path, env
        end
        error[#error+1] = table.concat(args, " ")
        error[#error+1] = table.concat(err, "\n")
        error[#error+1] = ""
    end
    log.fastfail(table.concat(error, "\n"))
end

local function getEnvironment(arch, winsdk, toolset)
    local path, env = vsdevcmd(arch, winsdk, toolset)
    if not path then
        return
    end
    installationPath = path
    UniversalCRTSdkDir = env.UniversalCRTSdkDir

    local environment = {}
    for name, value in pairs(env) do
        local NAME = name:upper()
        if need[NAME] then
            environment[NAME] = value
        end
    end
    if not winsdk then
        globals.winsdk = find_winsdk()
    end
    if not toolset then
        globals.toolset = find_toolset()
    end
    return environment
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
    return installationPath.."/VC/Tools/MSVC/"..toolset
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
        local verfile = installationPath.."/VC/Auxiliary/Build/Microsoft.VCRedistVersion.default.txt"
        local r = readall(verfile)
        return strtrim(r)
    end)()
    local ToolsetVersion = (function ()
        local verfile = toolspath(toolset).."/include/yvals_core.h"
        local r = readall(verfile)
        return r:match "#define%s+_MSVC_STL_VERSION%s+(%d+)"
    end)()
    local path = installationPath.."/VC/Redist/MSVC/"..RedistVersion
    if optimize == "off" then
        return path.."/debug_nonredist/"..arch.."/Microsoft.VC"..ToolsetVersion..".DebugCRT"
    end
    return path.."/"..arch.."/Microsoft.VC"..ToolsetVersion..".CRT"
end

local function ucrtpath(arch, optimize)
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
    local path = installationPath.."/VC/Tools/Llvm/x64/lib/clang/"
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
    arm64 = "arm64",
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

do
    local arch = globals.arch
    local rebuild = arguments.what == "rebuild"
    local console_cp = getConsoleCP()
    if not rebuild and m.hasEnvConfig() then
        local config = readEnvConfig()
        if config.arch == arch
            and (not console_cp or config.console_cp == console_cp)
            and config.toolset
            and config.installationPath
            and fs.exists(config.installationPath.."/VC/Tools/MSVC/"..config.toolset)
        then
            installationPath = config.installationPath
            env = config.env
            msvc_deps_prefix = config.prefix
            globals.winsdk = config.winsdk
            globals.toolset = config.toolset
            return m
        end
    end
    env = getEnvironment(ArchAlias[arch], globals.winsdk, globals.toolset)
    msvc_deps_prefix = getMsvcDepsPrefix(env)

    local s = {}
    s[#s+1] = "return {"
    s[#s+1] = ("installationPath=%q,"):format(installationPath)
    s[#s+1] = ("console_cp=%q,"):format(console_cp)
    s[#s+1] = ("arch=%q,"):format(arch)
    if globals.winsdk then
        s[#s+1] = ("winsdk=%q,"):format(globals.winsdk)
    end
    s[#s+1] = ("toolset=%q,"):format(globals.toolset)
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

return m
