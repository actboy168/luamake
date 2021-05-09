local arguments = require "arguments"
local globals = require "globals"
local sp = require 'bee.subprocess'
local thread = require 'bee.thread'

local function ninja(args)
    if globals.compiler == 'msvc' then
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
    local build_ninja = (WORKDIR / globals.builddir / arguments.f):replace_extension ".ninja"
    table.insert(args, 2, "-f")
    table.insert(args, 3, build_ninja)
    args.stderr = true
    args.stdout = true
    args.cwd = WORKDIR
    local process = assert(sp.spawn(args))

    local errmsg = {}
    while true do
        local outn = sp.peek(process.stdout)
        if outn == nil then
            errmsg[#errmsg+1] = process.stderr:read "a"
            break
        elseif outn ~= 0 then
            io.write(process.stdout:read(outn))
        end
        local errn = sp.peek(process.stderr)
        if errn == nil then
            io.write(process.stdout:read "a")
            break
        elseif errn ~= 0 then
            errmsg[#errmsg+1] = process.stderr:read(errn)
        end
        if outn == 0 and errn == 0 then
            io.flush()
            thread.sleep(0.01)
        end
    end

    if #errmsg > 0 then
        io.write(table.concat(errmsg))
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
