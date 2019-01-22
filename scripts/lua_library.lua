local fs = require "bee.filesystem"
local inited = false

local function copy_dir(from, to)
    fs.create_directories(to)
    for file in from:list_directory() do
        if not fs.is_directory(file) then
            fs.copy_file(file, to / file:filename(), true)
        end
    end
end

local function init(lm)
    if inited then
        return
    end
    inited = true
    local w = lm.writer
    w:rule("luadef", [[$luamake lua build/lua_def.lua -in $in -out $out]],
    {
        description = 'Lua def $out',
    })
    if lm.cc.name == 'cl' then
        w:rule("luadeps", [[lib /nologo /machine:i386 /def:$in /out:$out]],
        {
            description = 'Lua import lib $out'
        })
    elseif lm.cc.name == 'gcc' then
        w:rule("luadeps", [[dlltool -d $in -l $out]],
        {
            description = 'Lua import lib $out'
        })
    end
end

local function windowsDeps(lm, name, attribute, include, luaversion)
    local w = lm.writer
    local cc = lm.cc
    local windeps = include / "windeps"
    fs.create_directories(WORKDIR / 'build' / luaversion / "windeps")
    fs.copy_file(MAKEDIR / "scripts" / "lua_def.lua", WORKDIR / 'build' / "lua_def.lua", true)

    local ldflags = attribute.ldflags or {}
    local input = attribute.input or {}

    w:build(windeps / "lua.def", "luadef", include)

    if cc.name == "cl" then
        ldflags[#ldflags+1] = "/EXPORT:luaopen_" .. name
        w:build(windeps / "lua.lib", "luadeps", windeps / "lua.def")
        input[#input+1] = windeps / "lua.lib"
    else
        w:build(windeps / "liblua.a", "luadeps", windeps / "lua.def")
        input[#input+1] = windeps / "liblua.a"
    end
    attribute.ldflags = ldflags
    attribute.input = input
end

return function (lm, name, attribute)
    init(lm)
    local flags = attribute.flags or {}
    local luaversion = attribute.luaversion or "lua54"
    local include = fs.path('build') / luaversion
    flags[#flags+1] = lm.cc.includedir(include)
    attribute.flags = flags
    copy_dir(MAKEDIR / "tools" / luaversion, WORKDIR / 'build' / luaversion)
    if lm.plat == "msvc" or lm.plat == "mingw" then
        windowsDeps(lm, name, attribute, include, luaversion)
    end
    return lm, 'shared_library', name, attribute
end
