local platform = require "bee.platform"
local sp = require "bee.subprocess"
local fs = require "bee.filesystem"
local lm = LUAMAKE
local w = lm.writer

w:rule("luadef", [[$makedir/luamake.exe lua $makedir/scripts/common/lua_def.lua -name lua54.dll -in $in -out $out]],
{
    description = 'Lua def $out'
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

local function windowsDeps(cc, name, attribute)
    local include = fs.path('$makedir') / "tools" / "lua54"
    local windeps = include / "windeps"
    fs.create_directories(MAKEDIR / "tools" / "lua54" / "windeps")

    local ldflags = attribute.ldflags or {}
    local implicit = attribute.implicit or {}

    ldflags[#ldflags+1] = cc.linkdir(windeps)
    ldflags[#ldflags+1] = cc.link("lua54")

    w:build(windeps / "lua54.def", "luadef", include)

    if cc.name == "cl" then
        ldflags[#ldflags+1] = "/EXPORT:luaopen_" .. name
        w:build(windeps / "lua54.lib", "luadeps", windeps / "lua54.def")
        implicit[#implicit+1] = windeps / "lua54.lib"
    else
        w:build(windeps / "liblua54.a", "luadeps", windeps / "lua54.def")
        implicit[#implicit+1] = windeps / "liblua54.a"
    end
    attribute.ldflags = ldflags
    attribute.implicit = implicit
end

return function (name)
    return function (attribute)
        local flags = attribute.flags or {}
        flags[#flags+1] = lm.cc.includedir(MAKEDIR / "tools" / "lua54")
        attribute.flags = flags
        if platform.OS == "Windows" then
            windowsDeps(lm.cc, name, attribute)
        end

        lm:shared_library(name)(attribute)
    end
end
