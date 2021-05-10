local fs = require "bee.filesystem"
local lua_def = require "lua_def"
local inited_rule = false
local inited_version = {}

local function copy_dir(from, to)
    fs.create_directories(to)
    for file in from:list_directory() do
        if not fs.is_directory(file) then
            fs.copy_file(file, to / file:filename(), fs.copy_options.update_existing)
        end
    end
end

local function init_rule(lm, globals, arch)
    if inited_rule then
        return
    end
    inited_rule = true
    local ninja = lm.ninja
    if globals.compiler == 'msvc' then
        ninja:rule("luadeps", ([[lib /nologo /machine:%s /def:$in /out:$out]]):format(arch),
        {
            description = 'Lua import lib $out'
        })
    else
        ninja:rule("luadeps", [[dlltool -d $in -l $out]],
        {
            description = 'Lua import lib $out'
        })
    end
end

local function init_version(lm, globals, arch, luadir, luaversion)
    if inited_version[luaversion] then
        return
    end
    inited_version[luaversion] = true
    local ninja = lm.ninja
    lua_def(MAKEDIR / "tools" / luaversion)
    if globals == 'msvc' then
        ninja:build(luadir / ("lua_"..arch..".lib"), "luadeps", luadir / "lua.def")
    else
        ninja:build(luadir / "liblua.a", "luadeps", luadir / "lua.def")
    end
end

local function windows_deps(_, name, attribute, globals, arch, luadir)
    local ldflags = attribute.ldflags or {}
    local input = attribute.input or {}
    ldflags = type(ldflags) == "string" and {ldflags} or ldflags
    input = type(input) == "string" and {input} or input
    if globals.compiler == "msvc" then
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
    local luadir = fs.path(globals.builddir) / luaversion
    flags[#flags+1] = lm.cc.includedir(luadir:string())
    attribute.flags = flags

    if globals.os == "windows" then
        local arch = globals.target
        init_rule(lm, globals, arch)
        init_version(lm, globals, arch, luadir, luaversion)
        windows_deps(lm, name, attribute, globals, arch, luadir)
    end
    copy_dir(MAKEDIR / "tools" / luaversion, luadir)
    return lm, 'shared_library', name, attribute, globals
end
