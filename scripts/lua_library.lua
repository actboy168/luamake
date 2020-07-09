local fs = require "bee.filesystem"
local arguments = require "arguments"
local inited_rule = false
local inited_version = {}

local function copy_dir(from, to)
    fs.create_directories(to)
    for file in from:list_directory() do
        if not fs.is_directory(file) then
            fs.copy_file(file, to / file:filename(), true)
        end
    end
end

local function init_rule(lm, arch)
    if inited_rule then
        return
    end
    inited_rule = true
    local ninja = lm.ninja
    ninja:rule("luadef", [[$luamake lua build/lua_def.lua -in $in -out $out]],
    {
        description = 'Lua def $out',
    })
    if lm.cc.name == 'cl' then
        ninja:rule("luadeps", ([[lib /nologo /machine:%s /def:$in /out:$out]]):format(arch),
        {
            description = 'Lua import lib $out'
        })
    elseif lm.cc.name == 'gcc' then
        ninja:rule("luadeps", [[dlltool -d $in -l $out]],
        {
            description = 'Lua import lib $out'
        })
    end
end

local function init_version(lm, luaversion, arch)
    if inited_version[luaversion] then
        return
    end
    inited_version[luaversion] = true
    local ninja = lm.ninja
    local include = fs.path('build') / luaversion
    local windeps = include / "windeps"
    ninja:build(windeps / "lua.def", "luadef", include)
    if lm.cc.name == 'cl' then
        ninja:build(windeps / ("lua_"..arch..".lib"), "luadeps", windeps / "lua.def")
    elseif lm.cc.name == 'gcc' then
        ninja:build(windeps / "liblua.a", "luadeps", windeps / "lua.def")
    end
end

local function windowsDeps(lm, name, attribute, include, luaversion, arch)
    local cc = lm.cc
    local windeps = include / "windeps"
    fs.create_directories(WORKDIR / 'build' / luaversion / "windeps")
    fs.copy_file(MAKEDIR / "scripts" / "lua_def.lua", WORKDIR / 'build' / "lua_def.lua", true)

    local ldflags = attribute.ldflags or {}
    local input = attribute.input or {}
    ldflags = type(ldflags) == "string" and {ldflags} or ldflags
    input = type(input) == "string" and {input} or input

    if cc.name == "cl" then
        if attribute.export_luaopen ~= false then
            ldflags[#ldflags+1] = "/EXPORT:luaopen_" .. name
        end
        input[#input+1] = windeps / ("lua_"..arch..".lib")
    else
        input[#input+1] = windeps / "liblua.a"
    end
    attribute.ldflags = ldflags
    attribute.input = input
end

return function (lm, name, attribute, globals)
    local flags = attribute.flags or {}
    local luaversion = attribute.luaversion or "lua54"
    local include = fs.path('build') / luaversion
    local arch = lm.arch

    if arguments.plat == "msvc" or arguments.plat == "mingw" then
        init_rule(lm, arch)
        init_version(lm, luaversion, arch)
    end

    flags[#flags+1] = lm.cc.includedir(include)
    attribute.flags = flags
    copy_dir(MAKEDIR / "tools" / luaversion, WORKDIR / 'build' / luaversion)
    if arguments.plat == "msvc" or arguments.plat == "mingw" then
        windowsDeps(lm, name, attribute, include, luaversion, arch)
    end
    return lm, 'shared_library', name, attribute, globals
end
