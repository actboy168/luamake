local sp = require 'bee.subprocess'
local fs = require 'bee.filesystem'

local function Is64BitWindows()
    -- https://docs.microsoft.com/en-us/archive/blogs/david.wang/howto-detect-process-bitness
    return os.getenv "PROCESSOR_ARCHITECTURE" == "AMD64" or os.getenv "PROCESSOR_ARCHITEW6432" == "AMD64"
end

local ProgramFiles = Is64BitWindows() and 'ProgramFiles(x86)' or 'ProgramFiles'
local vswhere = os.getenv(ProgramFiles)..'/Microsoft Visual Studio/Installer/vswhere.exe'
local need = { LIB = true, LIBPATH = true, PATH = true, INCLUDE = true }

local function writeall(filename, content)
    local f <close> = assert(io.open(filename, 'w'))
    if content then
        f:write(content)
    end
end

local function readall(filename)
    local f <close> = assert(io.open(filename, 'r'))
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
        '-nologo',
        '-latest',
        --'-prerelease',
        '-utf8',
        '-products', '*',
        '-requires', 'Microsoft.VisualStudio.Component.VC.Tools.x86.x64',
        '-property', 'installationPath',
        stdout = true,
        stderr = "stdout",
    })
    local result = strtrim(process.stdout:read 'a')
    process.stdout:close()
    local code = process:wait()
    if code ~= 0 then
        print("[vswhere]", result)
        os.exit(code, true)
    end
    InstallDir = result
    return InstallDir
end

local function parse_env(str)
    local pos = str:find('=')
    if not pos then
        return
    end
    return strtrim(str:sub(1, pos - 1)), strtrim(str:sub(pos + 1))
end

local function findwinsdk()
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
                if version:sub(1,3) == "10." then
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

local function vsdevcmd(winsdk, arch, f)
    local vsvars32 = installpath()..'/Common7/Tools/VsDevCmd.bat'
    local args = { vsvars32 }
    if arch then
        args[#args+1] = ('-arch=%s'):format(arch)
    end
    if winsdk then
        args[#args+1] = ('-winsdk=%s'):format(winsdk)
    end
    local process = assert(sp.spawn {
        args, '&&', 'set',
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
    local code = process:wait()
    if code ~= 0 then
        io.stderr:write("Call `VsDevCmd.bat` error:\n")
        io.stderr:write(err)
        os.exit(code, true)
    end
end

local function environment(winsdk, arch)
    local env = {}
    vsdevcmd(winsdk, arch, function (name, value)
        name = name:upper()
        if need[name] then
            env[name] = value
        end
    end)
    return env
end

local function prefix(env)
    local testdir = os.tmpname()
    fs.create_directories(testdir)
    writeall(testdir..'/test.c', '#include <stddef.h>')
    writeall(testdir..'/build.ninja', [[
rule showIncludes
  command = cl /nologo /showIncludes -c $in
build test: showIncludes test.c
]])
    local process = assert(sp.spawn {
        'cmd', '/c', 'ninja',
        searchPath = true,
        env = env,
        cwd = testdir,
        stdout = true,
        --stderr = "stdout",
    })
    local result
    for line in process.stdout:lines() do
        local m = line:match('[^:]+:[^:]+:')
        if m then
            result = m
            break
        end
    end
    process.stdout:close()
    process:wait()
    fs.remove_all(testdir)
    assert(result, "can't find msvc.")
    return result
end

local function toolspath()
    local ToolsVersion = (function ()
        local verfile = installpath()..'/VC/Auxiliary/Build/Microsoft.VCToolsVersion.default.txt'
        local r = readall(verfile)
        return strtrim(r)
    end)()
    return installpath()..'/VC/Tools/MSVC/'..ToolsVersion
end

local function binpath(arch)
    local host = Is64BitWindows() and "Hostx64" or "Hostx86"
    return toolspath()..'/bin/'..host..'/'..arch
end

local function vcrtpath(arch, mode)
    local RedistVersion = (function ()
        local verfile = installpath()..'/VC/Auxiliary/Build/Microsoft.VCRedistVersion.default.txt'
        local r = readall(verfile)
        return strtrim(r)
    end)()
    local ToolsetVersion = (function ()
        local verfile = toolspath()..'/include/yvals_core.h'
        local r = readall(verfile)
        return r:match '#define%s+_MSVC_STL_VERSION%s+(%d+)'
    end)()
    local path = installpath()..'/VC/Redist/MSVC/'..RedistVersion
    if mode ~= "release" then
        return path.."/debug_nonredist/"..arch..'/Microsoft.VC'..ToolsetVersion..'.DebugCRT'
    end
    return path..'/'..arch..'/Microsoft.VC'..ToolsetVersion..'.CRT'
end

local function ucrtpath(arch, mode)
    local UniversalCRTSdkDir
    vsdevcmd(findwinsdk(), arch, function (name, value)
        if name == "UniversalCRTSdkDir" then
            UniversalCRTSdkDir = value
        end
    end)
    if not UniversalCRTSdkDir then
        return
    end
    local path = UniversalCRTSdkDir..'/Redist'
    local redist, ver
    local function accept(p, version)
        local ucrt = p..'/ucrt/DLLs/'..arch
        if fs.exists(ucrt) then
            if not ver or ver < version then
                redist, ver = ucrt, version
            end
        end
    end
    accept(path, 0)
    for p in fs.pairs(path) do
        local version = p:filename():string():gsub('10%.0%.([0-9]+)%.0', '%1')
        version = tonumber(version)
        accept(p:string(), version)
    end
    if not redist then
        return
    end
    if mode ~= "release" then
        if ver == 0 then
            --TODO 不一定合理，但至少比0好
            ver = 17134
        end
        return redist, UniversalCRTSdkDir.."/bin/10.0."..ver..".0/"..arch.."/ucrt"
    end
    return redist
end

return {
    installpath = installpath,
    toolspath = toolspath,
    environment = environment,
    prefix = prefix,
    binpath = binpath,
    vcrtpath = vcrtpath,
    ucrtpath = ucrtpath,
    findwinsdk = findwinsdk
}
