local platform = require "bee.platform"
local sp = require "bee.subprocess"
local fs = require "bee.filesystem"
local lm = LUAMAKE
local w = lm.writer

w:rule("luadef", [[$makedir/luamake.exe lua $makedir/scripts/common/lua_def.lua -in $in -out $out]],
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

local function windowsDeps(cc, name, attribute, luaversion)
    local include = fs.path('$makedir') / "tools" / luaversion
    local windeps = include / "windeps"
    fs.create_directories(MAKEDIR / "tools" / luaversion / "windeps")

    local ldflags = attribute.ldflags or {}
    local implicit = attribute.implicit or {}

    ldflags[#ldflags+1] = cc.linkdir(windeps)
    ldflags[#ldflags+1] = cc.link("lua")

    w:build(windeps / "lua.def", "luadef", include)

    if cc.name == "cl" then
        ldflags[#ldflags+1] = "/EXPORT:luaopen_" .. name
        w:build(windeps / "lua.lib", "luadeps", windeps / "lua.def")
        implicit[#implicit+1] = windeps / "lua.lib"
    else
        w:build(windeps / "liblua.a", "luadeps", windeps / "lua.def")
        implicit[#implicit+1] = windeps / "liblua.a"
    end
    attribute.ldflags = ldflags
    attribute.implicit = implicit
end

return function (name)
    return function (attribute)
        local flags = attribute.flags or {}
        local luaversion = attribute.luaversion or "lua54"
        flags[#flags+1] = lm.cc.includedir(MAKEDIR / "tools" / luaversion)
        attribute.flags = flags
        if platform.OS == "Windows" then
            windowsDeps(lm.cc, name, attribute, luaversion)
        end

        lm:shared_library(name)(attribute)
    end
end
