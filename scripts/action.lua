local globals = require "globals"
local sp = require "bee.subprocess"
local fs = require "bee.filesystem"
local sim = require "simulator"
local arguments = require "arguments"

local function execute(option)
    local redirect = option.stdout ~= nil
    option.stdout = option.stdout or true
    option.stderr = "stdout"
    option.searchPath = true
    if globals.compiler == "msvc" then
        local msvc = require "msvc_util"
        option.env = msvc.getEnv()
        option.env.VS_UNICODE_OUTPUT = false
        option.env.TMP = fs.absolute(globals.builddir):string()
    end
    if globals.hostshell == "cmd" then
        option[1] = { "cmd", "/c", option[1] }
    end
    local process = assert(sp.spawn(option))
    if not redirect then
        for line in process.stdout:lines() do
            io.write(line, "\n")
            io.flush()
        end
        process.stdout:close()
    end
    local code = process:wait()
    if code ~= 0 then
        os.exit(code)
    end
end

local function ninja(args)
    args[1] = { "ninja", "-f", globals.builddir.."/build.ninja", args[1] }
    execute(args)
end

local function init()
    sim.init()
    sim.import(arguments.f)
end

local function compdb()
    if globals.compile_commands then
        local compile_commands = globals.compile_commands:gsub("$(%w+)", {
            builddir = globals.builddir,
        })
        local f <close> = assert(io.open(compile_commands.."/compile_commands.json", "wb"))
        ninja {
            "-t", "compdb",
            stdout = f
        }
    end
end

local function generate()
    sim.generate()
    compdb()
end

local function build()
    local options = {}
    for _, opt in ipairs { "h", "v", "j", "k", "l", "n", "d", "t", "w" } do
        if arguments[opt] then
            table.insert(options, {
                "-"..opt,
                arguments[opt] ~= "on" and arguments[opt] or nil
            })
        end
    end
    ninja { arguments.targets, options }
end

local function clean()
    ninja { "-t", "clean" }
end

if globals.perf then
    local perf = require "perf"
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
    local function perf_build()
        local _ <close> = perf_single "build"
        return build()
    end
    local function perf_clean()
        local _ <close> = perf_single "clean"
        return clean()
    end
    return {
        init = perf_init,
        generate = perf_generate,
        build = perf_build,
        clean = perf_clean,
    }
end

return {
    init = init,
    generate = generate,
    build = build,
    clean = clean,
    execute = execute,
}
