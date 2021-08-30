local globals = require "globals"
local sp = require 'bee.subprocess'
local thread = require 'bee.thread'
local sim = require 'simulator'

local function ninja(args)
    local option = {
        "ninja", "-f",  WORKDIR / globals.builddir / "build.ninja",
        args,
        stdout = true,
        stderr = "stdout",
        cwd = WORKDIR,
        searchPath = true,
    }
    if globals.compiler == 'msvc' then
        local msvc = require "msvc_util"
        option.env = msvc.getEnv()
        option.env.VS_UNICODE_OUTPUT = false
        option[1] = {'cmd', '/c', 'ninja'}
    end

    local process = assert(sp.spawn(option))
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
    sim.import(WORKDIR / "make.lua")
end

local function generate()
    sim.generate()
end

local function make()
    local arguments = require "arguments"
    ninja(arguments.targets)
end

local function clean()
    ninja { "-t", "clean" }
end

if globals.perf then
    local monotonic = require 'bee.time'.monotonic
    local perf_status = {}
    local function perf_end()
        local time = monotonic() - perf_status[2]
        print(("%s: %dms."):format(perf_status[1], time))
    end
    local function perf(what)
        perf_status[1] = what
        perf_status[2] = monotonic()
        return perf_status
    end
    setmetatable(perf_status, {__close = perf_end})

    local function perf_init(...)
        local _ <close> = perf "init"
        return init(...)
    end
    local function perf_generate(...)
        local _ <close> = perf "generate"
        return generate(...)
    end
    local function perf_make(...)
        local _ <close> = perf "make"
        return make(...)
    end
    local function perf_clean(...)
        local _ <close> = perf "clean"
        return clean(...)
    end
    return {
        init = perf_init,
        generate = perf_generate,
        make = perf_make,
        clean = perf_clean,
    }
end

return {
    init = init,
    generate = generate,
    make = make,
    clean = clean,
}
