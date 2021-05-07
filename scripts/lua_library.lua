local fs = require "bee.filesystem"
local arguments = require "arguments"
local lua_def = require "lua_def"
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
    local luadir = fs.path('build') / luaversion
    lua_def(MAKEDIR / "tools" / luaversion)
    if lm.cc.name == 'cl' then
        ninja:build(luadir / ("lua_"..arch..".lib"), "luadeps", luadir / "lua.def")
    elseif lm.cc.name == 'gcc' then
        ninja:build(luadir / "liblua.a", "luadeps", luadir / "lua.def")
    end
end

local function windows_deps(lm, name, attribute, luadir, arch)
    local cc = lm.cc
    local ldflags = attribute.ldflags or {}
    local input = attribute.input or {}
    ldflags = type(ldflags) == "string" and {ldflags} or ldflags
    input = type(input) == "string" and {input} or input
    if cc.name == "cl" then
        if attribute.export_luaopen ~= false and (not attribute.msvc or attribute.msvc.export_luaopen ~= false) then
            ldflags[#ldflags+1] = "/EXPORT:luaopen_" .. name
        end
        input[#input+1] = luadir / ("lua_"..arch..".lib")
    else
        input[#input+1] = luadir / "liblua.a"
    end
    attribute.ldflags = ldflags
    attribute.input = input
end

return function (lm, name, attribute, globals)
    local flags = attribute.flags or {}
    local luaversion = attribute.luaversion or "lua54"
    local luadir = fs.path('build') / luaversion
    flags[#flags+1] = lm.cc.includedir(luadir:string())
    attribute.flags = flags

    if arguments.plat == "msvc" or arguments.plat == "mingw" then
        local arch = lm.target
        init_rule(lm, arch)
        init_version(lm, luaversion, arch)
        windows_deps(lm, name, attribute, luadir, arch)
    end
    copy_dir(MAKEDIR / "tools" / luaversion, WORKDIR / 'build' / luaversion)
    return lm, 'shared_library', name, attribute, globals
end
