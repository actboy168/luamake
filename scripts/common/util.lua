local sp = require 'bee.subprocess'
local platform = require 'bee.platform'

local function isMsvc()
    if platform.OS == 'Windows' and os.getenv 'MSYSTEM' == nil then
        return true
    end
    return false
end

local function ninja(args)
    if isMsvc() then
        if #args == 0 then
            local msvc = require 'common.msvc'
            if args.env then
                for k, v in pairs(msvc.env) do
                    args.env[k] = v
                end
            else
                args.env = msvc.env
            end
        end
        table.insert(args, 1, MAKEDIR / "tools" / 'ninja.exe')
    else
        args.searchPath = true
        table.insert(args, 1, 'ninja')
    end
    local build_ninja = (WORKDIR / 'build' / (ARGUMENTS.f or 'make.lua')):replace_extension(".ninja")
    table.insert(args, 2, "-f")
    table.insert(args, 3, build_ninja)
    args.stderr = true
    args.stdout = true
    args.cwd = WORKDIR
    if args.env then
        args.env.VS_UNICODE_OUTPUT = false
    else
        args.env = {
            VS_UNICODE_OUTPUT = false
        }
    end
    local process = assert(sp.spawn(args))
    for line in process.stdout:lines() do
        print(line)
    end
    io.write(process.stderr:read 'a')
    process:wait()
end

local function command(what, ...)
    local path = assert(package.searchpath(what, (MAKEDIR / "scripts" / "command" / "?.lua"):string()))
    assert(loadfile(path))(...)
end

return {
    ninja = ninja,
    command = command,
}
