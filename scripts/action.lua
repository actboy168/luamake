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

if globals.perf then
    local pref_status = {}
    local function pref_end()
        local time = os.clock() - pref_status[2]
        print(("%s: %.3fms."):format(pref_status[1], time * 1000.))
    end
    local function pref(what)
        pref_status[1] = what
        pref_status[2] = os.clock()
        return pref_status
    end
    setmetatable(pref_status, {__close = pref_end})

    local function pref_init(...)
        local _ <close> = pref "init"
        return init(...)
    end
    local function pref_generate(...)
        local _ <close> = pref "generate"
        return generate(...)
    end
    local function pref_make(...)
        local _ <close> = pref "make"
        return make(...)
    end
    local function pref_clean(...)
        local _ <close> = pref "clean"
        return clean(...)
    end
    return {
        init = pref_init,
        generate = pref_generate,
        make = pref_make,
        clean = pref_clean,
    }
end

return {
    init = init,
    generate = generate,
    make = make,
    clean = clean,
}
