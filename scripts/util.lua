local globals = require "globals"
local sp = require 'bee.subprocess'

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

    while true do
        local n = sp.peek(process.stdout)
        if n == nil then
            local s = process.stdout:read "a"
            if s then
                io.write(s)
                io.flush()
            end
            break
        end
        if n > 0 then
            io.write(process.stdout:read(n))
            io.flush()
        end
    end

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

local function cmd_init(dontgenerate)
    local sim = require 'simulator'
    sim:dofile(WORKDIR / "make.lua")
    if not dontgenerate then
        sim:finish()
    end
end

local function cmd_make()
    local arguments = require "arguments"
    ninja(arguments.targets)
end

local function cmd_clean()
    ninja { "-t", "clean" }
end

return {
    command = command,
    sandbox = sandbox,
    cmd_init = cmd_init,
    cmd_make = cmd_make,
    cmd_clean = cmd_clean,
}
