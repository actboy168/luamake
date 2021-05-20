local arguments = require "arguments"
local globals = require "globals"
local sp = require 'bee.subprocess'
local thread = require 'bee.thread'

local function ninja(args)
    if globals.compiler == 'msvc' then
        local msvc = require "msvc_util"
        if args.env then
            for k, v in pairs(msvc.getEnv()) do
                args.env[k] = v
            end
        else
            args.env = msvc.getEnv()
        end
        args.env.VS_UNICODE_OUTPUT = false
        args.searchPath = true
        table.insert(args, 1, {'cmd', '/c', 'ninja'})
    else
        args.searchPath = true
        table.insert(args, 1, 'ninja')
    end
    table.insert(args, 2, "-f")
    table.insert(args, 3, WORKDIR / globals.builddir / "build.ninja")
    args.stdout = true
    args.stderr = "stdout"
    args.cwd = WORKDIR
    local process = assert(sp.spawn(args))

    for line in process.stdout:lines() do
        io.write(line)
        io.write "\n"
    end
    io.flush()

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
        preload = globals.compiler == 'msvc' and {
            msvc = require "msvc",
        },
        builddir = globals.builddir,
    })(...)
end


return {
    ninja = ninja,
    command = command,
    sandbox = sandbox,
}
