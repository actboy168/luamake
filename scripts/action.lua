local globals = require "globals"
local sp = require 'bee.subprocess'
local thread = require 'bee.thread'
local sim = require 'simulator'

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
        else
            thread.sleep(1)
        end
    end

    local code = process:wait()
    if code ~= 0 then
        os.exit(code, true)
    end
end

local function init()
    sim:dofile(WORKDIR / "make.lua")
end

local function generate()
    sim:finish()
end

local function make()
    local arguments = require "arguments"
    ninja(arguments.targets)
end

local function clean()
    ninja { "-t", "clean" }
end

return {
    init = init,
    generate = generate,
    make = make,
    clean = clean,
}
