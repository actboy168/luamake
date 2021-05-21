local fs = require "bee.filesystem"
local globals = require "globals"
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

local function init_single(attribute, attr_name, default)
    local attr = attribute[attr_name]
    if type(attr) == 'table' then
        attribute[attr_name] = attr[#attr]
    elseif attr == nil then
        attribute[attr_name] = default
    end
    return attribute[attr_name]
end

local function init_rule(lm)
    if inited_rule then
        return
    end
    inited_rule = true
    local ninja = lm.ninja
    if globals.compiler == 'msvc' then
        local msvc = require "msvc_util"
        ninja:rule("luadeps", ([[lib /nologo /machine:%s /def:$in /out:$out]]):format(msvc.archAlias(globals.arch)),
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

local function init_version(lm, luadir, luaversion)
    if inited_version[luaversion] then
        return
    end
    inited_version[luaversion] = true
    local ninja = lm.ninja
    lua_def(MAKEDIR / "tools" / luaversion)
    local libname
    if globals.compiler == 'msvc' then
        libname = luadir / ("lua-"..globals.arch..".lib")
        ninja:build(libname, "luadeps", luadir / "lua.def")
    else
        libname = luadir / "liblua.a"
        ninja:build(libname, "luadeps", luadir / "lua.def")
    end
    lm._targets["__"..luaversion.."__"] = {
        input = {libname}
    }
end

local function windows_deps(_, name, attribute, luaversion)
    local ldflags = attribute.ldflags or {}
    local deps = attribute.deps or {}
    if globals.compiler == "msvc" then
        local export_luaopen = init_single(attribute, "export_luaopen", "on")
        if export_luaopen ~= "off" then
            ldflags[#ldflags+1] = "/EXPORT:luaopen_" .. name
        end
    end
    deps[#deps+1] = "__"..luaversion.."__"
    attribute.ldflags = ldflags
    attribute.deps = deps
end

return function (lm, name, attribute)
    local luaversion = attribute.luaversion or "lua54"
    local luadir = fs.path(globals.builddir) / luaversion

    local includes = attribute.includes or {}
    includes[#includes+1] = "$builddir/"..luaversion
    attribute.includes = includes

    if globals.os == "windows" then
        init_rule(lm)
        init_version(lm, luadir, luaversion)
        windows_deps(lm, name, attribute, luaversion)
    end
    copy_dir(MAKEDIR / "tools" / luaversion, luadir)
    return lm, 'shared_library', name, attribute
end
