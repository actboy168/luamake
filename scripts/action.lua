local globals = require "globals"
local sp = require 'bee.subprocess'
local sim = require 'simulator'
local arguments = require "arguments"

local function spawn_ninja(args)
    local option = {
        "ninja", "-f",  globals.builddir .. "/build.ninja",
        args,
        stdout = args.stdout or true,
        stderr = "stdout",
        searchPath = true,
    }
    if globals.compiler == 'msvc' then
        local msvc = require "msvc_util"
        option.env = msvc.getEnv()
        option.env.VS_UNICODE_OUTPUT = false
        option.env.TMP = globals.builddir
    end
    if globals.hostshell == "cmd" then
        option[1] = {'cmd', '/c', 'ninja'}
    end

    return assert(sp.spawn(option))
end

local function ninja(args)
    local process = spawn_ninja(args)
    for line in process.stdout:lines() do
        io.write(line, "\n")
        io.flush()
    end
    process.stdout:close()

    local code = process:wait()
    if code ~= 0 then
        os.exit(code, true)
    end
end

local function init()
    sim.import(arguments.f)
end

local function compdb()
    if globals.compile_commands then
        local compile_commands = globals.compile_commands:gsub("$(%w+)", {
            builddir = globals.builddir,
        })
        local f <close> = assert(io.open(compile_commands.."/compile_commands.json", "wb"))
        local process = spawn_ninja {
            "-t", "compdb",
            stdout = f
        }
        assert(process:wait() == 0)
    end
end

local function generate()
    sim.generate()
    compdb()
end

local function make()
    local options = {}
    for _, opt in ipairs {"h", "v", "j", "k", "l", "n", "d", "t", "w"} do
        if arguments[opt] then
            table.insert(options, {
                "-"..opt,
                arguments[opt] ~= "on" and arguments[opt] or nil
            })
        end
    end
    ninja {arguments.targets, options}
end

local function clean()
    ninja {"-t", "clean"}
end

if globals.perf then
    local perf = require 'perf'
    local perf_single = perf.single
    local perf_print = perf.print
    local function perf_init()
        local _ <close> = perf_single "init"
        return init()
    end
    local function perf_generate()
        do
            local _ <close> = perf_single "generate"
            generate()
        end
        return perf_print()
    end
    local function perf_make()
        local _ <close> = perf_single "make"
        return make()
    end
    local function perf_clean()
        local _ <close> = perf_single "clean"
        return clean()
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
