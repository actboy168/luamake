local fs = require "bee.filesystem"
local sys = require "bee.sys"
local arguments = require "arguments"
local globals = require "globals"
local fsutil = require "fsutil"
local glob = require "glob"
local pathutil = require "pathutil"
local log = require "log"
local sandbox = require "sandbox"
local workspace = require "workspace"

local ninja
local cc

local m = {}
local loaded_target = {}
local loaded_rule = {}
local loaded_conf = {}
local scripts = {}
local visited = {}

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
    local v = attribute[attr_name]
    if v == nil then
        attribute[attr_name] = default
        v = default
    end
end

local function init_enum(attribute, attr_name, default, allow)
    local v = attribute[attr_name]
    if v == nil then
        attribute[attr_name] = default
        v = default
    end
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

local function normalize_rootdir(workdir, rootdir)
    return pathutil.tostr(workdir, rootdir)
end

local function reslove_attributes(g, l)
    local l_rootdir = normalize_rootdir(g.workdir, l.rootdir or g.rootdir)
    local t = {}
    workspace.push_attributes(t, g)
    if l.confs then
        for _, conf in ipairs(l.confs) do
            local conf_attribute = log.assert(loaded_conf[conf], "unknown conf `%s`", conf)
            workspace.push_attributes(t, conf_attribute)
        end
    end
    workspace.resolve_attributes(t, l, l_rootdir)
    t.workdir = g.workdir
    t.rootdir = l_rootdir
    return t
end

local function reslove_attributes_nolink(g, l)
    local l_rootdir = normalize_rootdir(g.workdir, l.rootdir or g.rootdir)
    local t = {}
    workspace.push_attributes(t, g, true)
    if l.confs then
        for _, conf in ipairs(l.confs) do
            local conf_attribute = log.assert(loaded_conf[conf], "unknown conf `%s`", conf)
            workspace.push_attributes(t, conf_attribute, true)
        end
    end
    workspace.resolve_attributes(t, l, l_rootdir)
    t.workdir = g.workdir
    t.rootdir = l_rootdir
    return t
end

local function reslove_args(args)
    local command = {}
    for i, v in ipairs(args) do
        command[i] = fsutil.quotearg(v)
    end
    return table.concat(command, " ")
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
local enum_luaversion <const> = { [""] = true, lua53 = true, lua54 = true, lua55 = true }

local function generate(rule, attribute, name)
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

    local bindir = attribute.bindir
    local sources = get_blob(attribute.rootdir, attribute.sources)
    local objargs = attribute.objdeps and { implicit_inputs = attribute.objdeps } or nil
    local implicit_inputs = {}

    init_single(attribute, "c", "")
    init_single(attribute, "cxx", "")

    init_enum(attribute, "mode", "release", enum_mode)
    init_enum(attribute, "crt", "dynamic", enum_crt)
    init_enum(attribute, "warnings", "on", cc.warnings)
    init_enum(attribute, "rtti", "on", enum_onoff)
    init_enum(attribute, "visibility", "hidden", enum_visibility)
    init_enum(attribute, "luaversion", "", enum_luaversion)
    init_enum(attribute, "optimize", (attribute.mode == "debug" and "off" or "speed"), cc.optimize)

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
    local inputs = get_blob(attribute.rootdir, attribute.inputs)
    local outputs = attribute.outputs or {}
    local implicit_inputs = getImplicitInputs(name, attribute)

    local n = #inputs
    for i = 1, #implicit_inputs do
        inputs[n + i] = implicit_inputs[i]
    end

    if name then
        if #outputs == 0 then
            if #inputs == 0 then
                log.fatal("`%s`: no input.", name)
            else
                ninja:phony(name, inputs)
            end
        else
            ninja:phony(name, outputs)
            for _, out in ipairs(outputs) do
                ninja:phony(out, inputs)
            end
        end
        loaded_target[name] = {
            implicit_inputs = name,
        }
    else
        if #outputs == 0 then
            log.fatal("no output.")
        else
            for _, out in ipairs(outputs) do
                ninja:phony(out, inputs)
            end
        end
    end
end

function GEN.runlua(attribute, name)
    local tmpName = not name
    name = name or generateTargetName()
    log.assert(loaded_target[name] == nil, "`%s`: redefinition.", name)
    local script = attribute.script
    log.assert(script, "`%s`: need attribute `script`.", name)

    local inputs = get_blob(attribute.rootdir, attribute.inputs)
    local outputs = attribute.outputs or {}
    local implicit_inputs = getImplicitInputs(name, attribute)
    implicit_inputs[#implicit_inputs+1] = script

    if attribute.args then
        local command = reslove_args(attribute.args)
        ninja:rule("runlua", "$luamake lua $script "..command, {
            description = "lua $script "..command
        })
    else
        ninja:rule("runlua", "$luamake lua $script", {
            description = "lua $script"
        })
    end

    local outname
    if #outputs == 0 then
        outname = "$builddir/_/"..name
    else
        outname = outputs
    end
    ninja:build(outname, inputs, {
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

    local inputs = get_blob(attribute.rootdir, attribute.inputs)
    local outputs = attribute.outputs or {}
    local implicit_inputs = getImplicitInputs(name, attribute)
    local rule = attribute.rule

    local outname
    if #outputs == 0 then
        outname = "$builddir/_/"..name
    else
        outname = outputs
    end

    if rule then
        log.assert(loaded_rule[rule], "unknown rule `%s`", rule)
        local command
        if attribute.args then
            command = reslove_args(attribute.args)
        end
        ninja:set_rule(rule)
        ninja:build(outname, inputs, {
            implicit_inputs = implicit_inputs,
            variables = { args = command },
        })
    else
        local command = reslove_args(attribute.args)
        ninja:rule("build_"..name, command)
        ninja:build(outname, inputs, {
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

local function generate_copy(implicit_inputs, inputs, outputs)
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
        for i = 1, #inputs do
            ninja:build(outputs[i], inputs[i])
        end
    else
        for i = 1, #inputs do
            ninja:build(outputs[i], nil, {
                implicit_inputs = implicit_inputs,
                variables = { input = inputs[i] },
            })
        end
    end
end

function GEN.copy(attribute, name)
    local inputs = attribute.inputs or {}
    local outputs = attribute.outputs or {}
    for i = 1, #inputs do
        inputs[i] = pathutil.tostr(attribute.rootdir, inputs[i])
    end
    local implicit_inputs = getImplicitInputs(name, attribute)
    log.assert(#inputs == #outputs, "`%s`: The number of input and output must be the same.", name)
    generate_copy(implicit_inputs, inputs, outputs)
    if name then
        log.assert(loaded_target[name] == nil, "`%s`: redefinition.", name)
        ninja:phony(name, outputs)
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
    local inputs = {}
    local outputs = {}
    local implicit_inputs = getImplicitInputs(name, attribute)
    init_enum(attribute, "mode", "release", enum_mode)
    init_enum(attribute, "optimize", (attribute.mode == "debug" and "off" or "speed"), cc.optimize)
    init_enum(attribute, "type", nil, enum_copy_type)

    local msvc = require "env.msvc"
    local archalias = msvc.archAlias(attribute.arch)
    local attributeOutputs = attribute.outputs

    if attribute.type == "vcrt" then
        local ignore = attribute.optimize == "off" and "vccorlib140d.dll" or "vccorlib140.dll"
        for dll in fs.pairs(msvc.vcrtpath(archalias, attribute.optimize, globals.toolset)) do
            local filename = dll:filename():string()
            if filename:lower() ~= ignore then
                for _, outputdir in ipairs(attributeOutputs) do
                    inputs[#inputs+1] = dll
                    outputs[#outputs+1] = fsutil.join(outputdir, filename)
                end
            end
        end
    elseif attribute.type == "ucrt" then
        local redist, bin = msvc.ucrtpath(archalias, attribute.optimize)
        if attribute.optimize == "off" then
            for dll in fs.pairs(redist) do
                local filename = dll:filename():string()
                if filename:lower() == "ucrtbase.dll" then
                    for _, outputdir in ipairs(attributeOutputs) do
                        inputs[#inputs+1] = fsutil.join(bin, "ucrtbased.dll")
                        outputs[#outputs+1] = fsutil.join(outputdir, "ucrtbased.dll")
                    end
                else
                    for _, outputdir in ipairs(attributeOutputs) do
                        inputs[#inputs+1] = dll
                        outputs[#outputs+1] = fsutil.join(outputdir, filename)
                    end
                end
            end
        else
            for dll in fs.pairs(redist) do
                local filename = dll:filename():string()
                for _, outputdir in ipairs(attributeOutputs) do
                    inputs[#inputs+1] = dll
                    outputs[#outputs+1] = fsutil.join(outputdir, filename)
                end
            end
        end
    elseif attribute.type == "asan" then
        local filename = ("clang_rt.asan_dynamic-%s.dll"):format(
            attribute.arch == "x86_64" and "x86_64" or "i386"
        )
        local inputdir = globals.cc == "clang-cl"
            and msvc.llvmpath()
            or msvc.binpath(archalias, globals.toolset)
        for _, outputdir in ipairs(attributeOutputs) do
            inputs[#inputs+1] = fsutil.join(inputdir, filename)
            outputs[#outputs+1] = fsutil.join(outputdir, filename)
        end
    end
    generate_copy(implicit_inputs, inputs, outputs)

    if name then
        log.assert(loaded_target[name] == nil, "`%s`: redefinition.", name)
        ninja:phony(name, outputs)
        loaded_target[name] = {
            implicit_inputs = name,
        }
    end
end

local function get_luamake()
    return fmtpath(sys.exe_path():string())
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

function m.init()
    ninja = require "ninja_writer" ()
    cc = require("compiler."..globals.compiler)
    ninja:switch_body()
end

function m.generate()
    ninja:switch_head()
    local builddir = fsutil.join(WORKDIR, globals.builddir)
    if globals.compiler == "msvc" then
        fs.create_directories(fsutil.join(builddir, "tmp"))
    else
        fs.create_directories(builddir)
    end

    ninja:variable("ninja_required_version", "1.7")
    ninja:variable("builddir", fmtpath(globals.builddir))
    ninja:variable("bin", fmtpath(globals.bindir))
    ninja:variable("obj", fmtpath(globals.objdir))

    if globals.os == "android" and globals.hostos ~= "android" then
        require "env.ndk"
    end
    if globals.compiler == "wasi" then
        require "env.wasi"
    end

    if globals.compiler == "msvc" then
        if not globals.prebuilt then
            local msvc = require "env.msvc"
            ninja:variable("msvc_deps_prefix", globals.cc == "clang-cl"
                and "Note: including file:"
                or msvc.getPrefix()
            )
        end
        ninja:variable("cc", globals.cc or "cl")
        if globals.arch == "x86_64" then
            ninja:variable("ml", "ml64")
        elseif globals.arch == "x86" then
            ninja:variable("ml", "ml")
        elseif globals.arch == "arm64" then
            ninja:variable("ml", "armasm64")
        end
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
            local attribute = reslove_attributes(global_attribute, local_attribute)
            attribute.luaversion = attribute.luaversion or "lua54"
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
        local attribute = reslove_attributes_nolink(global_attribute, local_attribute)
        attribute.luaversion = attribute.luaversion or "lua54"
        generate("source_set", attribute, name)
    end
end

local alias <const> = {
    exe = "executable",
    dll = "shared_library",
    lib = "static_library",
    src = "source_set",
}
for to, from in pairs(alias) do
    api[to] = api[from]
end

for rule, genfunc in pairs(GEN) do
    api[rule] = function (global_attribute, name)
        if type(name) == "table" then
            local local_attribute = name
            local attribute = reslove_attributes(global_attribute, local_attribute)
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

function api.rule(global_attribute, name)
    log.assert(type(name) == "string", "Name is not a string.")
    return function (local_attribute)
        local attribute = reslove_attributes(global_attribute, local_attribute)
        log.assert(loaded_rule[name] == nil, "rule `%s`: redefinition.", name)
        loaded_rule[name] = true
        if attribute.deps then
            attribute.deps = attribute.deps[#attribute.deps]
        end
        local command = reslove_args(attribute.args)
        ninja:rule(name, command, attribute)
    end
end

function api.conf(global_attribute, name)
    if type(name) == "table" then
        local local_attribute = name
        local root = normalize_rootdir(global_attribute.workdir, local_attribute.rootdir or global_attribute.rootdir)
        local attribute = {}
        workspace.resolve_attributes(attribute, local_attribute, root)
        global_attribute("set", attribute)
    else
        log.assert(type(name) == "string", "Name is not a string.")
        return function (local_attribute)
            local root = normalize_rootdir(global_attribute.workdir, local_attribute.rootdir or global_attribute.rootdir)
            local attribute = {}
            workspace.resolve_attributes(attribute, local_attribute, root)
            loaded_conf[name] = attribute
        end
    end
end

function api:has(name)
    log.assert(type(name) == "string", "Name is not a string.")
    return loaded_target[name] ~= nil
end

function api:path(value)
    return pathutil.create(self.workdir, value)
end

function api:required_version(buildVersion)
    local function parse_version(v)
        local major, minor = v:match "^(%d+)%.(%d+)"
        if not major then
            log.fastfail("Invalid version string: `%s`.", v)
        end
        return tonumber(major) * 1000 + tonumber(minor)
    end
    local luamakeVersion = require "version"
    if parse_version(luamakeVersion) < parse_version(buildVersion) then
        log.fastfail("luamake version (%s) incompatible with build file required_version (%s).", luamakeVersion, buildVersion)
    end
end

local MainWorkspace = workspace.create(globals.workdir, api, globals)

function api:default(targets)
    if self == MainWorkspace then
        local deps = {}
        workspace.push_strings(deps, targets)
        local implicit_inputs = getImplicitInputs("default", { deps = deps })
        ninja:default(implicit_inputs)
    end
end

local function openfile(name, mode)
    local f, err = io.open(name, mode)
    if f and (mode == nil or mode:match "r") then
        if not scripts[name] then
            scripts[name] = true
            scripts[#scripts+1] = fsutil.relative(name, WORKDIR)
        end
    end
    return f, err
end

local function importfile(ws, rootdir, filename)
    local subws = ws and workspace.create(rootdir, ws, {}) or MainWorkspace
    sandbox {
        rootdir = rootdir,
        builddir = globals.builddir,
        preload = {
            luamake = subws,
        },
        openfile = openfile,
        main = filename,
        args = {}
    }
end

function api:import(path)
    local ws = self
    local fullpath = pathutil.tostr(ws.workdir, path)
    if visited[fullpath] then
        return
    end
    visited[fullpath] = true
    local rootdir = fsutil.parent_path(fullpath)
    local filename = fsutil.filename(fullpath)
    importfile(ws, rootdir, filename)
end

function m.import(path)
    importfile(nil, WORKDIR, path or "make.lua")
end

api.pcall = log.pcall
api.xpcall = log.xpcall

return m
