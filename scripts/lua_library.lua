local platform = require "bee.platform"
local fs = require "bee.filesystem"
local inited = false

local function init(lm)
    if inited then
        return
    end
    inited = true
    local w = lm.writer
    w:rule("luadef", [[$makedir/luamake.exe lua $makedir/scripts/lua_def.lua -in $in -out $out]],
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

local function windowsDeps(lm, name, attribute, luaversion)
    local w = lm.writer
    local cc = lm.cc
    local include = fs.path('$makedir') / "tools" / luaversion
    local windeps = include / "windeps"
    fs.create_directories(MAKEDIR / "tools" / luaversion / "windeps")

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
    flags[#flags+1] = lm.cc.includedir(MAKEDIR / "tools" / luaversion)
    attribute.flags = flags
    if platform.OS == "Windows" then
        windowsDeps(lm, name, attribute, luaversion)
    end
    return lm, 'shared_library', name, attribute
end
