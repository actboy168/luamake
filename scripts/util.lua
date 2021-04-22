local arguments = require "arguments"
local sp = require 'bee.subprocess'

local function script()
    return (WORKDIR / 'build' / arguments.plat / arguments.f):replace_extension ".ninja"
end

local function ninja(args)
    if arguments.plat == 'msvc' then
        local msvc = require "msvc_util"
        if args.env then
            for k, v in pairs(msvc.getenv()) do
                args.env[k] = v
            end
        else
            args.env = msvc.getenv()
        end
        args.env.VS_UNICODE_OUTPUT = false
        args.searchPath = true
        table.insert(args, 1, {'cmd', '/c', 'ninja'})
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
        io.write(line)
        io.write "\n"
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
    assert(require "sandbox"{
        root = WORKDIR:string(),
        main = filename,
        io_open = io.open,
        preload = arguments.plat == 'msvc' and {
            msvc = require "msvc",
        },
        plat = arguments.plat,
    })(...)
end


return {
    ninja = ninja,
    command = command,
    script = script,
    sandbox = sandbox,
}
