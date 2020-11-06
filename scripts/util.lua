local arguments = require "arguments"
local sp = require 'bee.subprocess'

local function script()
    return (WORKDIR / 'build' / arguments.plat / arguments.f):replace_extension ".ninja"
end

local function ninja(args)
    if arguments.plat == 'msvc' then
        if #args == 0 then
            local msvc = require "msvc"
            if args.env then
                for k, v in pairs(msvc.getenv()) do
                    args.env[k] = v
                end
            else
                args.env = msvc.getenv()
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
    local code = process:wait()
    if code ~= 0 then
        os.exit(code, true)
    end
end

local function command(what, ...)
    local path = assert(package.searchpath(what, (MAKEDIR / "scripts" / "command" / "?.lua"):string()))
    assert(loadfile(path))(...)
end

local function sandbox(filename, ...)
    local env = arguments.plat == 'msvc' and {
        msvc = require "msvc_helper",
    }
    assert(require "sandbox"(WORKDIR:string(), filename, io.open, env))(...)
end


return {
    ninja = ninja,
    command = command,
    script = script,
    sandbox = sandbox,
}
