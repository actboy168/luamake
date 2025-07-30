local globals = require "globals"
local sp = require "bee.subprocess"
local fs = require "bee.filesystem"
local writer = require "writer"
local arguments = require "arguments"

local function execute(option)
    assert(option.stdout ~= nil)
    option.stderr = "stdout"
    option.searchPath = true
    if globals.compiler == "msvc" then
        local msvc = require "env.msvc"
        option.env = msvc.getEnv()
        option.env.VS_UNICODE_OUTPUT = false
        option.env.TMP = (fs.absolute(globals.builddir) / "tmp"):string()
    end
    if globals.hostshell == "cmd" then
        option[1] = { "cmd", "/c", option[1] }
    end
    local process = assert(sp.spawn(option))
    return process:wait()
end

local function ninja(args)
    args[1] = { globals.ninja or "ninja", "-f", globals.builddir.."/build.ninja", args[1] }
    return execute(args)
end

local function init()
    writer.init()
end

local function import()
    writer.import(arguments.f)
end

local function compdb()
    if globals.compile_commands then
        local compile_commands = globals.compile_commands:gsub("$(%w+)", {
            builddir = globals.builddir,
        })
        local f <close> = assert(io.open(compile_commands.."/compile_commands.json", "wb"))
        ninja {
            "-t", "compdb", "-x",
            stdout = f,
        }
    end
end

local function generate()
    writer.generate()
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
    local code = ninja {
        arguments.targets, options,
        stdout = io.stdout,
    }
    if code ~= 0 then
        os.exit(code)
    end
end

local function clean()
    local code = ninja {
        "-t", "clean",
        stdout = io.stdout,
    }
    if code ~= 0 then
        os.exit(code)
    end
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
    import = import,
    generate = generate,
    build = build,
    clean = clean,
    execute = execute,
}
