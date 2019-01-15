local sp = require 'bee.subprocess'
local platform = require 'bee.platform'
local fs = require 'bee.filesystem'

local plat, compiler = (function ()
    if platform.OS == "Windows" then
        if os.getenv "MSYSTEM" then
            return "mingw", "gcc"
        end
        return "msvc", "cl"
    elseif platform.OS == "Linux" then
        return "linux", "gcc"
    elseif platform.OS == "macOS" then
        return "macos", "clang"
    end
end)()

local function script(v)
    local builddir = v and fs.path('$builddir') or (WORKDIR / 'build')
    local filename = builddir / (ARGUMENTS.f or 'make.lua')
    return filename:parent_path() / ("%s-%s.ninja"):format(filename:stem():string(), plat)
end

local function ninja(args)
    if plat == 'msvc' then
        if #args == 0 then
            local msvc = require "msvc"
            if args.env then
                for k, v in pairs(msvc.env) do
                    args.env[k] = v
                end
            else
                args.env = msvc.env
            end
        end
        if args.env then
            args.env.VS_UNICODE_OUTPUT = false
        else
            args.env = {
                VS_UNICODE_OUTPUT = false
            }
        end
        table.insert(args, 1, MAKEDIR / "tools" / 'ninja.exe')
    else
        args.searchPath = true
        table.insert(args, 1, 'ninja')
    end
    local build_ninja = script()
    table.insert(args, 2, "-f")
    table.insert(args, 3, build_ninja)
    args.stderr = true
    args.stdout = true
    args.cwd = WORKDIR
    local process = assert(sp.spawn(args))
    for line in process.stdout:lines() do
        print(line)
    end
    io.write(process.stderr:read 'a')
    process:wait()
end

local function command(what, ...)
    local path = assert(package.searchpath(what, (MAKEDIR / "scripts" / "command" / "?.lua"):string()))
    assert(loadfile(path))(...)
end

return {
    ninja = ninja,
    command = command,
    script = script,
    plat = plat,
    compiler = compiler,
}
