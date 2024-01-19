local fs = require "bee.filesystem"
local arguments = require "arguments"
local globals = require "globals"
local fsutil = require "fsutil"
local glob = require "glob"
local pathutil = require "pathutil"
local log = require "log"

local ninja
local cc

local m = {}
local loaded_target = {}
local loaded_rule = {}
local loaded_config = {}
local scripts = {}

local file_type <const> = {
    cxx = "cxx",
    cpp = "cxx",
    cc = "cxx",
    mm = "cxx",
    c = "c",
    m = "c",
    rc = "rc",
    s = "asm",
    asm = "asm",
    def = "raw",
    obj = "raw",
}

local function fmtpath(p)
    return p:gsub("\\", "/")
end

local function init_single(attribute, attr_name, default)
    local attr = attribute[attr_name]
    if type(attr) == "table" then
        attribute[attr_name] = attr[#attr]
    elseif attr == nil then
        attribute[attr_name] = default
    end
end

local function init_enum(attribute, attr_name, default, allow)
    init_single(attribute, attr_name, default)
    local v = attribute[attr_name]
    if allow[v] == nil then
        local str = {}
        for k in pairs(allow) do
            str[#str+1] = "  - "..k
        end
        table.sort(str)
        table.insert(str, 1, ("The value `%s` of attribute `%s` is invalid. Allowed values:"):format(v, attr_name))
        log.fatal(table.concat(str, "\n"))
    end
end

local function get_blob(rootdir, lst)
    if type(lst) ~= "table" then
        return {}
    end
    local result = glob(rootdir, lst)
    for i, r in ipairs(result) do
        result[i] = fsutil.relative(r, WORKDIR)
    end
    table.sort(result)
    return result
end

local function tbl_append(t, a)
    table.move(a, 1, #a, #t + 1, t)
end

local function tbl_insert(t, pos, a)
    for i = 1, #a do
        table.insert(t, pos + i - 1, a[i])
    end
end

local PlatformAttribute <const> = 0
local PlatformPath <const> = 1
local PlatformArgs <const> = 2

local ATTRIBUTE <const> = {
    -- os
    windows     = PlatformAttribute,
    linux       = PlatformAttribute,
    macos       = PlatformAttribute,
    ios         = PlatformAttribute,
    android     = PlatformAttribute,
    -- cc
    msvc        = PlatformAttribute,
    gcc         = PlatformAttribute,
    clang       = PlatformAttribute,
    clang_cl    = PlatformAttribute,
    mingw       = PlatformAttribute,
    emcc        = PlatformAttribute,
    -- path
    includes    = PlatformPath,
    sysincludes = PlatformPath,
    linkdirs    = PlatformPath,
    input       = PlatformPath,
    output      = PlatformPath,
    script      = PlatformPath,
    -- other
    args        = PlatformArgs,
}

local LINK_ATTRIBUTE <const> = {
    ldflags = true,
    links = true,
    linkdirs = true,
    frameworks = true,
}

local SKIP_CONFIG_ATTRIBUTE = {
    rootdir = true,
    workdir = true,
}
for k, v in pairs(ATTRIBUTE) do
    if v == PlatformAttribute then
        SKIP_CONFIG_ATTRIBUTE[k] = true
    end
end

local function push_string(t, a)
    if type(a) == "string" then
        t[#t+1] = a
    elseif type(a) == "userdata" then
        t[#t+1] = a
    elseif type(a) == "table" then
        if getmetatable(a) ~= nil then
            t[#t+1] = a
        else
            for _, e in ipairs(a) do
                push_string(t, e)
            end
        end
    end
end

local function push_path(t, a, root)
    if type(a) == "string" then
        t[#t+1] = pathutil.tostring(root, a)
    elseif type(a) == "userdata" then
        t[#t+1] = pathutil.tostring(root, a)
    elseif type(a) == "table" then
        if getmetatable(a) ~= nil then
            t[#t+1] = pathutil.tostring(root, a)
        else
            for _, e in ipairs(a) do
                push_path(t, e, root)
            end
        end
    end
end

local function push_mix(t, a, root)
    if type(a) == "string" then
        if a:sub(1, 1) == "@" then
            t[#t+1] = pathutil.tostring(root, a:sub(2))
        else
            t[#t+1] = a:gsub("@{([^}]*)}", function (s)
                return pathutil.tostring(root, s)
            end)
        end
    elseif type(a) == "userdata" then
        t[#t+1] = pathutil.tostring(root, a)
    elseif type(a) == "table" then
        if getmetatable(a) ~= nil then
            t[#t+1] = pathutil.tostring(root, a)
        else
            for _, e in ipairs(a) do
                push_mix(t, e, root)
            end
        end
    end
end

local function push_args(r, t, root)
    for _, v in ipairs(t) do
        push_mix(r, v, root)
    end
end

local function merge_table(root, t, a)
    for k, v in pairs(a) do
        if type(k) ~= "string" then
            goto continue
        end
        if ATTRIBUTE[k] == PlatformAttribute then
            goto continue
        end
        t[k] = t[k] or {}
        if ATTRIBUTE[k] == PlatformPath then
            push_path(t[k], v, root)
        elseif ATTRIBUTE[k] == PlatformArgs then
            push_args(t[k], v, root)
        else
            push_string(t[k], v)
        end
        if #t[k] == 0 then
            t[k] = nil
        end
        ::continue::
    end
    return t
end

local function merge_table_nolink(root, t, a)
    for k, v in pairs(a) do
        if type(k) ~= "string" then
            goto continue
        end
        if ATTRIBUTE[k] == PlatformAttribute then
            goto continue
        end
        if LINK_ATTRIBUTE[k] then
            goto continue
        end
        t[k] = t[k] or {}
        if ATTRIBUTE[k] == PlatformPath then
            push_path(t[k], v, root)
        elseif ATTRIBUTE[k] == PlatformArgs then
            push_args(t[k], v, root)
        else
            push_string(t[k], v)
        end
        if #t[k] == 0 then
            t[k] = nil
        end
        ::continue::
    end
    return t
end

local function reslove_table(root, t, a)
    merge_table(root, t, a)
    if a[globals.os] then
        merge_table(root, t, a[globals.os])
    end
    if a[globals.compiler] then
        merge_table(root, t, a[globals.compiler])
    end
    if a.mingw and globals.os == "windows" and globals.hostshell == "sh" then
        merge_table(root, t, a.mingw)
    end
    if a.clang_cl and globals.cc == "clang-cl" then
        merge_table(root, t, a.clang_cl)
    end
end

local function reslove_table_nolink(root, t, a)
    merge_table_nolink(root, t, a)
    if a[globals.os] then
        merge_table_nolink(root, t, a[globals.os])
    end
    if a[globals.compiler] then
        merge_table_nolink(root, t, a[globals.compiler])
    end
    if a.mingw and globals.os == "windows" and globals.hostshell == "sh" then
        merge_table_nolink(root, t, a.mingw)
    end
    if a.clang_cl and globals.cc == "clang-cl" then
        merge_table(root, t, a.clang_cl)
    end
end

local function normalize_rootdir(workdir, rootdir)
    if type(rootdir) == "table" then
        if getmetatable(rootdir) == nil then
            rootdir = rootdir[#rootdir]
        else
            --TODO
            rootdir = tostring(rootdir)
            return fsutil.absolute(WORKDIR, rootdir)
        end
    end
    return fsutil.normalize(workdir, rootdir or ".")
end

local function reslove_configs(attributes, configs, link)
    if not configs then
        return
    end
    local mark = {}
    for _, name in ipairs(configs) do
        if not mark[name] then
            mark[name] = true
            log.assert(loaded_config[name], "can`t find config `%s`", name)
            local config = loaded_config[name]
            for k, v in pairs(config) do
                if type(k) ~= "string" then
                    goto continue
                end
                if SKIP_CONFIG_ATTRIBUTE[k] then
                    goto continue
                end
                if LINK_ATTRIBUTE[k] ~= link then
                    goto continue
                end
                attributes[k] = attributes[k] or {}
                push_string(attributes[k], v)
                if #attributes[k] == 0 then
                    attributes[k] = nil
                end
                ::continue::
            end
        end
    end
end

local function reslove_attributes(g, loc)
    local g_rootdir = normalize_rootdir(g.workdir, g.rootdir)
    local l_rootdir = normalize_rootdir(g.workdir, loc.rootdir or g.rootdir)

    local r = {}
    reslove_table(g_rootdir, r, g)
    reslove_table(l_rootdir, r, loc)
    --TODO: remove it
    push_args(r, loc, l_rootdir)
    r.workdir = g.workdir
    r.rootdir = l_rootdir
    return r
end

local function reslove_attributes_local(g, loc)
    local l_rootdir = normalize_rootdir(g.workdir, loc.rootdir or g.rootdir)
    local r = {}
    reslove_table(l_rootdir, r, loc)
    --TODO: remove it
    push_args(r, loc, l_rootdir)
    r.workdir = g.workdir
    r.rootdir = l_rootdir
    return r
end

local function reslove_attributes_nolink(g, loc)
    local g_rootdir = normalize_rootdir(g.workdir, g.rootdir)
    local l_rootdir = normalize_rootdir(g.workdir, loc.rootdir or g.rootdir)

    local r = {}
    reslove_table_nolink(g_rootdir, r, g)
    reslove_table(l_rootdir, r, loc)
    --TODO: remove it
    push_args(r, loc, l_rootdir)
    r.workdir = g.workdir
    r.rootdir = l_rootdir
    return r
end

local function array_remove(t, k)
    for pos, v in ipairs(t) do
        if v == k then
            table.remove(t, pos)
            return true
        end
    end
    return false
end

local function update_flags(flags, cflags, cxxflags, attribute, name, rule)
    local defines = attribute.defines or {}

    tbl_append(flags, cc.flags)
    flags[#flags+1] = cc.optimize[attribute.optimize]
    flags[#flags+1] = cc.warnings[attribute.warnings]
    if globals.os ~= "windows" then
        if attribute.visibility ~= "default" then
            flags[#flags+1] = ("-fvisibility=%s"):format(attribute.visibility)
        end
        if rule == "shared_library" then
            flags[#flags+1] = "-fPIC"
        end
    end
    log.assert(cc.c[attribute.c], "`%s`: unknown std c: `%s`", name, attribute.c)
    log.assert(cc.cxx[attribute.cxx], "`%s`: unknown std c++: `%s`", name, attribute.cxx)
    cflags[#cflags+1] = cc.c[attribute.c]
    cxxflags[#cxxflags+1] = cc.cxx[attribute.cxx]
    cc.update_flags(flags, cflags, cxxflags, attribute, name)

    if attribute.includes then
        for _, inc in ipairs(attribute.includes) do
            flags[#flags+1] = cc.includedir(inc)
        end
    end

    if attribute.sysincludes then
        for _, inc in ipairs(attribute.sysincludes) do
            flags[#flags+1] = cc.sysincludedir(inc)
        end
    end

    if attribute.mode ~= "debug" then
        defines[#defines+1] = "NDEBUG"
    end

    if attribute.undefs then
        local undefs = attribute.undefs
        local pos = 1
        while pos <= #undefs do
            local macro = undefs[pos]
            if array_remove(defines, macro) then
                table.remove(undefs, pos)
            else
                pos = pos + 1
            end
        end
        for _, macro in ipairs(defines) do
            flags[#flags+1] = cc.define(macro)
        end
        for _, macro in ipairs(undefs) do
            flags[#flags+1] = cc.undef(macro)
        end
    else
        for _, macro in ipairs(defines) do
            flags[#flags+1] = cc.define(macro)
        end
    end

    if attribute.flags then
        tbl_append(flags, attribute.flags)
    end
end

local function update_ldflags(ldflags, attribute, name)
    tbl_append(ldflags, cc.ldflags)

    if attribute.links then
        for _, link in ipairs(attribute.links) do
            ldflags[#ldflags+1] = cc.link(link)
        end
    end
    if attribute.linkdirs then
        for _, linkdir in ipairs(attribute.linkdirs) do
            ldflags[#ldflags+1] = cc.linkdir(linkdir)
        end
    end
    if attribute.ldflags then
        tbl_append(ldflags, attribute.ldflags)
    end

    if attribute.deps then
        for _, dep in ipairs(attribute.deps) do
            local target = loaded_target[dep]
            log.assert(target, "`%s`: can`t find deps `%s`", name, dep)
            if target.ldflags then
                tbl_append(ldflags, target.ldflags)
            end
        end
    end

    cc.update_ldflags(ldflags, attribute, name)
end

local enum_onoff <const> = { on = true, off = true }
local enum_mode <const> = { release = true, debug = true }
local enum_crt <const> = { dynamic = true, static = true }
local enum_visibility <const> = { default = true, hidden = true }
local enum_luaversion <const> = { [""] = true, lua53 = true, lua54 = true }

local function generate(rule, attribute, name)
    reslove_configs(attribute, attribute.configs)
    local target = loaded_target[name]
    local input
    local ldflags
    local deps
    do
        if target then
            if target.rule == "source_set" then
                target.rule = rule
                input = target.input
                ldflags = target.ldflags
                deps = target.deps
                target.input = nil
                target.ldflags = nil
                target.deps = nil
            else
                log.fatal("`%s`: redefinition.", name)
            end
        else
            target = { rule = rule }
            input = {}
            ldflags = {}
            loaded_target[name] = target
        end
    end

    init_single(attribute, "bindir", globals.bindir)
    local bindir = attribute.bindir
    local sources = get_blob(attribute.rootdir, attribute.sources)
    local objargs = attribute.objdeps and { implicit_inputs = attribute.objdeps } or nil
    local implicit_inputs = {}

    init_enum(attribute, "mode", "release", enum_mode)
    init_enum(attribute, "crt", "dynamic", enum_crt)
    init_enum(attribute, "c", "", cc.c)
    init_enum(attribute, "cxx", "", cc.cxx)
    init_enum(attribute, "warnings", "on", cc.warnings)
    init_enum(attribute, "rtti", "on", enum_onoff)
    init_enum(attribute, "visibility", "hidden", enum_visibility)
    init_enum(attribute, "luaversion", "", enum_luaversion)
    init_enum(attribute, "optimize", (attribute.mode == "debug" and "off" or "speed"), cc.optimize)

    init_single(attribute, "target")
    init_single(attribute, "arch")
    init_single(attribute, "vendor")
    init_single(attribute, "sys")
    init_single(attribute, "basename")

    local default_enable_lto = attribute.mode ~= "debug" and globals.compiler == "msvc"
    init_enum(attribute, "lto", default_enable_lto and "on" or "off", enum_onoff)

    if globals.compiler == "msvc" then
        init_enum(attribute, "permissive", "off", enum_onoff)
    end

    if attribute.luaversion ~= "" then
        init_enum(attribute, "export_luaopen", "on", enum_onoff)
        require "lua_support" (ninja, loaded_target, rule, name, attribute)
    end

    if attribute.deps then
        if deps then
            tbl_append(deps, attribute.deps)
        else
            deps = attribute.deps
        end
    end

    local flags = {}
    local cflags = {}
    local cxxflags = {}
    update_flags(flags, cflags, cxxflags, attribute, name, rule)

    local str_flags = table.concat(flags, " ")
    local str_cflags = table.concat(cflags, " ")
    local str_cxxflags = table.concat(cxxflags, " ")
    for _, source in ipairs(sources) do
        local ext = fsutil.extension(source):sub(2):lower()
        local type = file_type[ext]
        if type == "raw" then
            input[#input+1] = source
            goto continue
        end
        local objpath = fsutil.join("$obj", name, fsutil.filename(source))
        if type == "c" then
            cc.rule_c(ninja, name, str_flags, str_cflags)
            input[#input+1] = ninja:build_obj(objpath, source, objargs)
        elseif type == "cxx" then
            cc.rule_cxx(ninja, name, str_flags, str_cxxflags)
            input[#input+1] = ninja:build_obj(objpath, source, objargs)
        elseif globals.os == "windows" and type == "rc" then
            cc.rule_rc(ninja, name)
            input[#input+1] = ninja:build_obj(objpath, source, objargs)
        elseif type == "asm" then
            cc.rule_asm(ninja, name, str_flags)
            input[#input+1] = ninja:build_obj(objpath, source, objargs)
        else
            log.fatal("`%s`: unknown file extension: `%s` in `%s`", name, ext, source)
        end
        ::continue::
    end

    if rule == "source_set" then
        if attribute.links then
            for _, link in ipairs(attribute.links) do
                ldflags[#ldflags+1] = cc.link(link)
            end
        end
        if attribute.linkdirs then
            for _, linkdir in ipairs(attribute.linkdirs) do
                ldflags[#ldflags+1] = cc.linkdir(linkdir)
            end
        end
        if attribute.ldflags then
            tbl_append(ldflags, attribute.ldflags)
        end
        if globals.compiler == "clang" and attribute.frameworks then
            for _, framework in ipairs(attribute.frameworks) do
                ldflags[#ldflags+1] = "-framework"
                ldflags[#ldflags+1] = framework
            end
        end
        target.input = input
        target.deps = deps
        target.ldflags = ldflags
        return
    end

    reslove_configs(attribute, attribute.configs, true)

    if deps then
        local mark = { [name] = true }
        local i = 1
        while i <= #deps do
            local dep = deps[i]
            if mark[dep] then
                table.remove(deps, i)
            else
                mark[dep] = true
                local t = loaded_target[dep]
                log.assert(t, "`%s`: deps `%s` undefine.", name, dep)
                if t.deps then
                    tbl_insert(deps, i + 1, t.deps)
                end
                i = i + 1
            end
        end
        for _, dep in ipairs(deps) do
            local t = loaded_target[dep]
            if t.input then
                tbl_append(input, t.input)
            end
            implicit_inputs[#implicit_inputs+1] = t.implicit_inputs
        end
    end
    log.assert(#input > 0, "`%s`: no source files found.", name)

    local binname
    if bindir == globals.bindir then
        bindir = "$bin"
    end
    update_ldflags(ldflags, attribute, name)

    local fin_ldflags = table.concat(ldflags, " ")
    local basename = attribute.basename or name
    if rule == "shared_library" then
        cc.rule_dll(ninja, name, fin_ldflags)
        if globals.compiler == "msvc" then
            binname = bindir.."/"..basename..".dll"
            local lib = ("$obj/%s/%s.lib"):format(name, basename)
            target.input = { lib }
            target.implicit_inputs = binname
            ninja:build(binname, input, {
                implicit_inputs = implicit_inputs,
                implicit_outputs = lib,
                variables = {
                    implib = lib,
                },
            })
        elseif globals.os == "windows" then
            binname = bindir.."/"..basename..".dll"
            target.input = { binname }
            ninja:build(binname, input, {
                implicit_inputs = implicit_inputs,
            })
        else
            if globals.compiler == "emcc" then
                binname = bindir.."/"..basename..".wasm"
            else
                binname = bindir.."/"..basename..".so"
            end
            target.implicit_inputs = binname
            ninja:build(binname, input, {
                implicit_inputs = implicit_inputs,
            })
        end
    elseif rule == "executable" then
        if globals.compiler == "emcc" then
            binname = bindir.."/"..basename..".js"
        elseif globals.os == "windows" then
            binname = bindir.."/"..basename..".exe"
        else
            binname = bindir.."/"..basename
        end
        target.implicit_inputs = binname
        cc.rule_exe(ninja, name, fin_ldflags)
        ninja:build(binname, input, {
            implicit_inputs = implicit_inputs,
        })
    elseif rule == "static_library" then
        if globals.os == "windows" then
            binname = bindir.."/"..basename..".lib"
        else
            binname = bindir.."/lib"..basename..".a"
        end
        target.input = { binname }
        cc.rule_lib(ninja, name)
        ninja:build(binname, input, {
            implicit_inputs = implicit_inputs,
        })
    end
    ninja:phony(name, binname)
end

local function generate_rule(attribute, name)
    log.assert(loaded_rule[name] == nil, "rule `%s`: redefinition.", name)
    loaded_rule[name] = true

    local command = {}
    for i, v in ipairs(attribute) do
        command[i] = fsutil.quotearg(v)
    end
    local kwargs = {}
    for k, v in pairs(attribute) do
        if type(k) == "string" then
            kwargs[k] = v[#v]
        end
    end
    ninja:rule(name, table.concat(command, " "), kwargs)
end

local function generate_config(attribute, name)
    log.assert(loaded_config[name] == nil, "config `%s`: redefinition.", name)
    loaded_config[name] = attribute
end

local function getImplicitInputs(name, attribute)
    local res = {}
    if attribute.deps then
        for _, dep in ipairs(attribute.deps) do
            local target = loaded_target[dep]
            if not target then
                if name then
                    log.fatal("`%s`: deps `%s` undefine.", name, dep)
                else
                    log.fatal("deps `%s` undefine.", dep)
                end
            end
            if target.input then
                tbl_append(res, target.input)
            end
            res[#res+1] = target.implicit_inputs
        end
    end
    return res
end

local GEN = {}

local NAMEIDX = 0
local function generateTargetName()
    NAMEIDX = NAMEIDX + 1
    return ("__target_0x%08x__"):format(NAMEIDX)
end

function GEN.phony(attribute, name)
    local input = attribute.input or {}
    local output = attribute.output or {}
    local implicit_inputs = getImplicitInputs(name, attribute)

    local n = #input
    for i = 1, #implicit_inputs do
        input[n + i] = implicit_inputs[i]
    end

    if name then
        if #output == 0 then
            if #input == 0 then
                log.fatal("`%s`: no input.", name)
            else
                ninja:phony(name, input)
            end
        else
            ninja:phony(name, output)
            for _, out in ipairs(output) do
                ninja:phony(out, input)
            end
        end
        loaded_target[name] = {
            implicit_inputs = name,
        }
    else
        if #output == 0 then
            log.fatal("`%s`: no output.", name)
        else
            for _, out in ipairs(output) do
                ninja:phony(out, input)
            end
        end
    end
end

function GEN.runlua(attribute, name)
    local tmpName = not name
    name = name or generateTargetName()
    log.assert(loaded_target[name] == nil, "`%s`: redefinition.", name)
    init_single(attribute, "script")
    local script = attribute.script
    log.assert(script, "`%s`: need attribute `script`.", name)

    local input
    if attribute.inputs then
        input = get_blob(attribute.rootdir, attribute.inputs)
    else
        input = attribute.input or {}
    end
    local output = attribute.output or {}
    local implicit_inputs = getImplicitInputs(name, attribute)
    implicit_inputs[#implicit_inputs+1] = script

    if attribute.args then
        local command = {}
        for i, v in ipairs(attribute.args) do
            command[i] = fsutil.quotearg(v)
        end
        local command_str = table.concat(command, " ")
        ninja:rule("runlua", "$luamake lua $script "..command_str, {
            description = "lua $script "..command_str
        })
    else
        ninja:rule("runlua", "$luamake lua $script", {
            description = "lua $script"
        })
    end


    local outname
    if #output == 0 then
        outname = "$builddir/_/"..name
    else
        outname = output
    end
    ninja:build(outname, input, {
        variables = {
            script = script,
        },
        implicit_inputs = implicit_inputs,
    })
    if not tmpName then
        ninja:phony(name, outname)
        loaded_target[name] = {
            implicit_inputs = name,
        }
    end
end

function GEN.build(attribute, name)
    local tmpName = not name
    name = name or generateTargetName()
    log.assert(loaded_target[name] == nil, "`%s`: redefinition.", name)
    init_single(attribute, "rule")

    local input
    if attribute.inputs then
        input = get_blob(attribute.rootdir, attribute.inputs)
    else
        input = attribute.input or {}
    end
    local output = attribute.output or {}
    local implicit_inputs = getImplicitInputs(name, attribute)
    local rule = attribute.rule

    local outname
    if #output == 0 then
        outname = "$builddir/_/"..name
    else
        outname = output
    end

    if rule then
        log.assert(loaded_rule[rule], "unknown rule `%s`", rule)
        ninja:set_rule(rule)
        local command_str; do
            if attribute.args then
                local command = {}
                for i, v in ipairs(attribute.args) do
                    command[i] = fsutil.quotearg(v)
                end
                command_str = table.concat(command, " ")
            end
        end
        ninja:build(outname, input, {
            implicit_inputs = implicit_inputs,
            variables = { args = command_str },
        })
    else
        local command = {}
        for i, v in ipairs(attribute) do
            command[i] = fsutil.quotearg(v)
        end
        ninja:rule("build_"..name, table.concat(command, " "))
        ninja:build(outname, input, {
            implicit_inputs = implicit_inputs,
        })
    end
    if not tmpName then
        ninja:phony(name, outname)
        loaded_target[name] = {
            implicit_inputs = name,
        }
    end
end

local function generate_copy(implicit_inputs, input, output)
    if globals.hostshell == "cmd" then
        ninja:rule("copy", "powershell -NonInteractive -Command Copy-Item -Path '$in$input' -Destination '$out' | Out-Null", {
            description = "Copy $in$input $out",
            restat = 1,
        })
    elseif globals.hostos == "windows" then
        ninja:rule("copy", 'sh -c "cp -fv $in$input $out 1>/dev/null"', {
            description = "Copy $in$input $out",
            restat = 1,
        })
    elseif globals.hostos == "macos" then
        -- see https://developer.apple.com/documentation/security/updating_mac_software
        ninja:rule("copy", "ditto $in$input $out 1>/dev/null", {
            description = "Copy $in$input $out",
            restat = 1,
        })
    else
        ninja:rule("copy", "cp -fv $in$input $out 1>/dev/null", {
            description = "Copy $in$input $out",
            restat = 1,
        })
    end

    if #implicit_inputs == 0 then
        for i = 1, #input do
            ninja:build(output[i], input[i])
        end
    else
        for i = 1, #input do
            ninja:build(output[i], nil, {
                implicit_inputs = implicit_inputs,
                variables = { input = input[i] },
            })
        end
    end
end

function GEN.copy(attribute, name)
    local input = attribute.input or {}
    local output = attribute.output or {}
    local implicit_inputs = getImplicitInputs(name, attribute)
    log.assert(#input == #output, "`%s`: The number of input and output must be the same.", name)
    generate_copy(implicit_inputs, input, output)
    if name then
        log.assert(loaded_target[name] == nil, "`%s`: redefinition.", name)
        ninja:phony(name, output)
        loaded_target[name] = {
            implicit_inputs = name,
        }
    end
end

local enum_copy_type <const> = { vcrt = true, ucrt = true, asan = true }

function GEN.msvc_copydll(attribute, name)
    if globals.compiler ~= "msvc" then
        return
    end
    local input = {}
    local output = {}
    local implicit_inputs = getImplicitInputs(name, attribute)
    init_enum(attribute, "mode", "release", enum_mode)
    init_enum(attribute, "optimize", (attribute.mode == "debug" and "off" or "speed"), cc.optimize)
    init_enum(attribute, "type", nil, enum_copy_type)
    init_single(attribute, "arch")

    local msvc = require "env.msvc"
    local outputdir = attribute.output[#attribute.output]
    local archalias = msvc.archAlias(attribute.arch)

    if attribute.type == "vcrt" then
        local ignore = attribute.optimize == "off" and "vccorlib140d.dll" or "vccorlib140.dll"
        for dll in fs.pairs(msvc.vcrtpath(archalias, attribute.optimize)) do
            local filename = dll:filename()
            if filename:string():lower() ~= ignore then
                input[#input+1] = dll
                output[#output+1] = outputdir / filename
            end
        end
    elseif attribute.type == "ucrt" then
        local redist, bin = msvc.ucrtpath(archalias, attribute.optimize)
        if attribute.optimize == "off" then
            for dll in fs.pairs(redist) do
                local filename = dll:filename()
                if filename:string():lower() == "ucrtbase.dll" then
                    input[#input+1] = fsutil.join(bin, "ucrtbased.dll")
                    output[#output+1] = fsutil.join(outputdir, "ucrtbased.dll")
                else
                    input[#input+1] = dll
                    output[#output+1] = outputdir / filename
                end
            end
        else
            for dll in fs.pairs(redist) do
                local filename = dll:filename()
                input[#input+1] = dll
                output[#output+1] = outputdir / filename
            end
        end
    elseif attribute.type == "asan" then
        local inputdir = msvc.binpath(archalias)
        local filename = ("clang_rt.asan_dynamic-%s.dll"):format(
            attribute.arch == "x86_64" and "x86_64" or "i386"
        )
        input[#input+1] = fsutil.join(inputdir, filename)
        output[#output+1] = fsutil.join(outputdir, filename)
    end
    generate_copy(implicit_inputs, input, output)

    if name then
        log.assert(loaded_target[name] == nil, "`%s`: redefinition.", name)
        ninja:phony(name, output)
        loaded_target[name] = {
            implicit_inputs = name,
        }
    end
end

local function get_luamake()
    local proc = arg[-1]
    if proc == "luamake" then
        return "luamake"
    end
    return fmtpath(fs.exe_path():string())
end

local function configure_args()
    local s = {}
    if arguments.C then
        s[#s+1] = "-C"
        s[#s+1] = arguments.C
    end
    for _, v in ipairs(arguments.targets) do
        s[#s+1] = v
    end
    for k, v in pairs(arguments.args) do
        s[#s+1] = "-"..k
        if v ~= "on" then
            s[#s+1] = v
        end
    end
    return table.concat(s, " ")
end

function m.add_script(p)
    if scripts[p] then
        return
    end
    scripts[p] = true
    scripts[#scripts+1] = fsutil.relative(p, WORKDIR)
end

function m.init()
    ninja = require "ninja_writer" ()
    cc = require("compiler."..globals.compiler)
    ninja:switch_body()
end

function m.default(attribute)
    local deps = {}
    push_string(deps, attribute)
    local implicit_inputs = getImplicitInputs("default", { deps = deps })
    ninja:default(implicit_inputs)
end

function m.generate()
    ninja:switch_head()
    local builddir = fsutil.join(WORKDIR, globals.builddir)
    fs.create_directories(builddir)

    ninja:variable("ninja_required_version", "1.7")
    ninja:variable("builddir", fmtpath(globals.builddir))
    ninja:variable("bin", fmtpath(globals.bindir))
    ninja:variable("obj", fmtpath(globals.objdir))

    if globals.os == "android" and globals.hostos ~= "android" then
        require "env.ndk"
    end

    if globals.compiler == "msvc" then
        if not globals.prebuilt then
            local msvc = require "env.msvc"
            msvc.createEnvConfig(globals.arch, arguments.what == "rebuild")
            ninja:variable("msvc_deps_prefix", globals.cc == "clang-cl"
                and "Note: including file:"
                or msvc.getPrefix()
            )
        end
        ninja:variable("cc", globals.cc or "cl")
        ninja:variable("ml", globals.arch == "x86_64" and "ml64" or "ml")
    else
        local compiler = globals.cc or globals.compiler
        if globals.hostshell == "cmd" then
            compiler = "cmd /c "..compiler
        end
        ninja:variable("cc", compiler)
        ninja:variable("ar", globals.ar or "ar")
    end

    if globals.prebuilt then
        ninja:variable("luamake", "luamake")
    else
        ninja:variable("luamake", get_luamake())
        ninja:rule("configure", "$luamake init "..configure_args(), { generator = 1 })
        ninja:build("$builddir/build.ninja", scripts)
    end

    local ninja_script = fsutil.join(builddir, "build.ninja")
    ninja:close(ninja_script)
end

local api = {}

local compile_target <const> = {
    "executable",
    "shared_library",
    "static_library",
}
for _, rule in ipairs(compile_target) do
    api[rule] = function (global_attribute, name)
        log.assert(type(name) == "string", "Name is not a string.")
        return function (local_attribute)
            local attribute = reslove_attributes(global_attribute, local_attribute)
            generate(rule, attribute, name)
        end
    end
end

local lua_compile_target <const> = {
    lua_exe = "executable",
    lua_dll = "shared_library",
    lua_lib = "static_library",
}
for rule, origin_rule in pairs(lua_compile_target) do
    api[rule] = function (global_attribute, name)
        log.assert(type(name) == "string", "Name is not a string.")
        return function (local_attribute)
            local_attribute.luaversion = local_attribute.luaversion or "lua54"
            local attribute = reslove_attributes(global_attribute, local_attribute)
            generate(origin_rule, attribute, name)
        end
    end
end

function api.source_set(global_attribute, name)
    log.assert(type(name) == "string", "Name is not a string.")
    return function (local_attribute)
        local attribute = reslove_attributes_nolink(global_attribute, local_attribute)
        generate("source_set", attribute, name)
    end
end

function api.lua_src(global_attribute, name)
    log.assert(type(name) == "string", "Name is not a string.")
    return function (local_attribute)
        local_attribute.luaversion = local_attribute.luaversion or "lua54"
        local attribute = reslove_attributes_nolink(global_attribute, local_attribute)
        generate("source_set", attribute, name)
    end
end

local alias <const> = {
    exe = "executable",
    dll = "shared_library",
    lib = "static_library",
    src = "source_set",
    lua_library = "lua_dll",
    lua_source = "lua_src",
}
for to, from in pairs(alias) do
    api[to] = api[from]
end

function api.rule(global_attribute, name)
    log.assert(type(name) == "string", "Name is not a string.")
    return function (local_attribute)
        local attribute = reslove_attributes(global_attribute, local_attribute)
        generate_rule(attribute, name)
    end
end

function api.config(global_attribute, name)
    log.assert(type(name) == "string", "Name is not a string.")
    return function (local_attribute)
        local attribute = reslove_attributes_local(global_attribute, local_attribute)
        generate_config(attribute, name)
    end
end

for rule, genfunc in pairs(GEN) do
    api[rule] = function (global_attribute, name)
        if type(name) == "table" then
            local attribute = reslove_attributes(global_attribute, name)
            genfunc(attribute)
        else
            log.assert(type(name) == "string", "Name is not a string.")
            return function (local_attribute)
                local attribute = reslove_attributes(global_attribute, local_attribute)
                genfunc(attribute, name)
            end
        end
    end
end

function api:has(name)
    log.assert(type(name) == "string", "Name is not a string.")
    return loaded_target[name] ~= nil
end

function api:path(value)
    return pathutil.create(value)
end

function api:required_version(buildVersion)
    local function parse_version(v)
        local major, minor = v:match "^(%d+)%.(%d+)"
        if not major then
            log.fatal("Invalid version string: `%s`.", v)
        end
        return tonumber(major) * 1000 + tonumber(minor)
    end
    local luamakeVersion = require "version"
    if parse_version(luamakeVersion) < parse_version(buildVersion) then
        log.fatal("luamake version (%s) incompatible with build file required_version (%s).", luamakeVersion, buildVersion)
    end
end

api.pcall = log.pcall
api.xpcall = log.xpcall

m.api = api

return m
