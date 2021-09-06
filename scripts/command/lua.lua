local fsutil = require "fsutil"

local function find_exe()
    local i = 0
    while arg[i] ~= nil do
        i = i - 1
    end
    return i + 1
end

local function update_arg()
    for i = 1, #arg do
        if arg[i] == "-e" then
            table.remove(arg, i)
            table.remove(arg, i)
            break
        end
    end

    if arg[2] == nil then
        error "Not found lua file."
    end
    arg[0] = arg[2]
    table.remove(arg, 1)
    table.remove(arg, 1)

    local idx = find_exe()
    arg[idx] = fsutil.quotearg(arg[idx]) .. " lua"
end

update_arg()

local globals = require "globals"
local sandbox = require "sandbox"

if globals.os == "windows" then
    local luadll = package.procdir.."/tools/lua54.dll"
    local ok, err = package.loadlib(luadll, "*")
    if not ok then
        --error(("could not be found: %s\n\t%s"):format(luadll, err))
    end
end

sandbox {
    rootdir = WORKDIR:string(),
    builddir = globals.builddir,
    preload = globals.compiler == 'msvc' and {
        msvc = require "msvc",
    },
    main = arg[0],
    args = arg,
}
