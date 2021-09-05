local fs = require "bee.filesystem"
local arguments = require "arguments"
local globals = require "globals"
local fsutil = require "fsutil"

local cc

local function fmtpath(context, path)
    if context.globals.hostshell == "cmd" then
        path = path:gsub('/', '\\')
    else
        path = path:gsub('\\', '/')
    end
    return path
end

local function fmtpath_v3(context, rootdir, path)
    path = tostring(path)
    if not fs.path(path):is_absolute() and path:sub(1, 1) ~= "$" then
        path = fsutil.normalize((rootdir / path):string())
        path = fsutil.relative(path, WORKDIR:string())
    end
    return fmtpath(context, path)
end

-- TODO 在某些平台上忽略大小写？
local function glob_compile(pattern)
    local sep = globals.hostshell == "cmd" and "\\/" or "/"
    return ("^%s$"):format(pattern
        :gsub("[%^%$%(%)%%%.%[%]%+%-%?]", "%%%0")
        :gsub("%*%*", "${d}")
        :gsub("%*", "${f}")
        :gsub("%$%{([^}]*)%}", {
            d = ".*",
            f = "[^"..sep.."]*",
        })
    )
end
local function glob_match(pattern, target)
    return target:match(pattern) ~= nil
end

local function accept_path(t, path)
    assert(fs.exists(path), ("source `%s` is not exists."):format(path:string()))
    local repath = fsutil.relative(path:string(), WORKDIR:string())
    if t[repath] then
        return
    end
    t[#t+1] = repath
    t[repath] = #t
end
local function expand_dir(t, pattern, dir)
    assert(fs.exists(dir), ("source dir `%s` is not exists."):format(dir:string()))
    for file in fs.pairs(dir) do
        if fs.is_directory(file) then
            expand_dir(t, pattern, file)
        else
            if glob_match(pattern, file:lexically_normal():string()) then
                accept_path(t, file)
            end
        end
    end
end

local function expand_path(t, path)
    local filename = path:lexically_normal():string()
    if filename:find("*", 1, true) == nil then
        accept_path(t, path)
        return
    end
    local pattern = glob_compile(filename)
    expand_dir(t, pattern, path:parent_path())
end

local function get_sources(root, sources)
    if type(sources) ~= "table" then
        return {}
    end
    local result = {}
    local ignore = {}
    for _, source in ipairs(sources) do
        if source:sub(1,1) ~= "!" then
            expand_path(result, root / source)
        else
            expand_path(ignore, root / source:sub(2))
        end
    end
    for _, path in ipairs(ignore) do
        local pos = result[path]
        if pos then
            result[pos] = result[#result]
            result[result[pos]] = pos
            result[path] = nil
            result[#result] = nil
        end
    end
    table.sort(result)
    return result
end

local file_type = {
    cxx = "cxx",
    cpp = "cxx",
    cc = "cxx",
    mm = "cxx",
    c = "c",
    m = "c",
    rc = "rc",
    s = "asm",
}

local function tbl_append(t, a)
    table.move(a, 1, #a, #t + 1, t)
end

local function pushTable(t, b)
    if type(b) == 'string' then
        t[#t+1] = b
    elseif type(b) == 'userdata' then
        t[#t+1] = b
    elseif type(b) == 'table' then
        for k, e in pairs(b) do
            if type(k) == "string" then
                if t[k] == nil then
                    t[k] = {}
                end
                pushTable(t[k], e)
            end
        end
        for _, e in ipairs(b) do
            pushTable(t, e)
        end
    end
    return t
end

local function mergeTable(a, b)
    for k, v in pairs(b) do
        if type(k) == "string" then
            local ov = a[k]
            if type(ov) == "table" then
                pushTable(ov, v)
            elseif not ov then
                local t = {}
                pushTable(t, v)
                a[k] = t
            else
                local t = {}
                pushTable(t, ov)
                pushTable(t, v)
                a[k] = t
            end
        end
    end
    for _, v in ipairs(b) do
        pushTable(a, v)
    end
    return a
end

local function reslovePlatformSpecific(a, b)
    local t = {}
    mergeTable(t, a)
    mergeTable(t, b)
    if t[globals.os] then
        mergeTable(t, t[globals.os])
    end
    if t[globals.compiler] then
        mergeTable(t, t[globals.compiler])
    end
    if t.mingw and globals.os == "windows" and globals.compiler == "gcc" then
        mergeTable(t, t.mingw)
    end
    return t
end

local function update_warnings(flags, warnings)
    if not warnings then
        flags[#flags+1] = cc.warnings["on"]
        return
    end

    warnings = reslovePlatformSpecific({}, warnings)
    local error = nil
    local level = 'on'
    for _, v in ipairs(warnings) do
        if v == 'error' then
            error = true
        elseif cc.warnings[v] then
            level = v
        end
    end
    flags[#flags+1] = cc.warnings[level]
    if error then
        flags[#flags+1] = cc.warnings.error
    end

    local disable = warnings.disable
    if disable then
        for _, v in ipairs(disable) do
            flags[#flags+1] = cc.disable_warning(v)
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

local function array_remove(t, k)
    for pos, m in ipairs(t) do
        if m == k then
            table.remove(t, pos)
            return true
        end
    end
    return false
end

local function update_flags(context, flags, attribute, name, rootdir, rule)
    local optimize = init_single(attribute, 'optimize', (attribute.mode == "debug" and "off" or "speed"))
    local defines = attribute.defines or {}

    tbl_append(flags, cc.flags)
    flags[#flags+1] = cc.optimize[optimize]
    update_warnings(flags, attribute.warnings)
    if context.globals.os ~= "windows" then
        local visibility = init_single(attribute, 'visibility', "hidden")
        if visibility ~= "default" then
            flags[#flags+1] = ('-fvisibility=%s'):format(visibility or 'hidden')
        end
        if rule == "shared_library" then
            flags[#flags+1] = "-fPIC"
        end
    end
    cc.update_flags(context, flags, attribute, name)

    if attribute.includes then
        for _, inc in ipairs(attribute.includes) do
            flags[#flags+1] = cc.includedir(fmtpath_v3(context, rootdir, inc))
        end
    end

    if attribute.mode == "release" then
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

local function update_ldflags(context, ldflags, attribute, name, rootdir)
    tbl_append(ldflags, cc.ldflags)

    if attribute.links then
        for _, link in ipairs(attribute.links) do
            ldflags[#ldflags+1] = cc.link(link)
        end
    end
    if attribute.linkdirs then
        for _, linkdir in ipairs(attribute.linkdirs) do
            ldflags[#ldflags+1] = cc.linkdir(fmtpath_v3(context, rootdir, linkdir))
        end
    end
    if attribute.ldflags then
        tbl_append(ldflags, attribute.ldflags)
    end

    if attribute.deps then
        for _, dep in ipairs(attribute.deps) do
            local target = context.loaded_targets[dep]
            assert(target ~= nil, ("`%s`: can`t find deps `%s`"):format(name, dep))
            if target.ldflags then
                tbl_append(ldflags, target.ldflags)
            end
        end
    end
    
    cc.update_ldflags(context, ldflags, attribute)
end

local function generate(context, rule, name, attribute)
    local target = context.loaded_targets[name]
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
                error(("`%s`: redefinition."):format(name))
            end
        else
            target = { rule = rule }
            input = {}
            ldflags =  {}
            context.loaded_targets[name] = target
        end
    end

    local ninja = context.ninja
    local workdir = fs.path(init_single(attribute, 'workdir', '.'))
    local rootdir = (workdir / init_single(attribute, 'rootdir', '.')):lexically_normal()
    local sources = get_sources(rootdir, attribute.sources)
    local implicit_input = {}

    init_single(attribute, 'mode', 'release')
    init_single(attribute, 'crt', 'dynamic')
    init_single(attribute, 'c', "c89")
    init_single(attribute, 'cxx', "c++17")
    init_single(attribute, 'visibility')
    init_single(attribute, 'target')
    init_single(attribute, 'arch')
    init_single(attribute, 'vendor')
    init_single(attribute, 'sys')

    if attribute.deps then
        if deps then
            tbl_append(deps, attribute.deps)
        else
            deps = attribute.deps
        end
    end

    local flags =  {}
    update_flags(context, flags, attribute, name, rootdir, rule)

    local fin_flags = table.concat(flags, " ")
    for _, source in ipairs(sources) do
        local objpath = fs.path("$obj") / name / fs.path(source):filename()
        local ext = fs.path(source):extension():string():sub(2):lower()
        local type = file_type[ext]
        if type == "c" then
            cc.rule_c(ninja, name, attribute, fin_flags)
            input[#input+1] = ninja:build_obj(objpath, source)
        elseif type == "cxx" then
            cc.rule_cxx(ninja, name, attribute, fin_flags)
            input[#input+1] = ninja:build_obj(objpath, source)
        elseif context.globals.os == "windows" and type == "rc" then
            cc.rule_rc(ninja, name)
            input[#input+1] = ninja:build_obj(objpath, source)
        elseif type == "asm" then
            if context.globals.compiler == "msvc" then
                error "TODO"
            end
            cc.rule_asm(ninja, name, fin_flags)
            input[#input+1] = ninja:build_obj(objpath, source)
        else
            error(("`%s`: unknown file extension: `%s` in `%s`"):format(name, ext, source))
        end
    end

    if rule == 'source_set' then
        if attribute.links then
            for _, link in ipairs(attribute.links) do
                ldflags[#ldflags+1] = cc.link(link)
            end
        end
        if attribute.linkdirs then
            for _, linkdir in ipairs(attribute.linkdirs) do
                ldflags[#ldflags+1] = cc.linkdir(fmtpath_v3(context, rootdir, linkdir))
            end
        end
        if attribute.ldflags then
            tbl_append(ldflags, attribute.ldflags)
        end
        if context.globals.compiler == "clang" and attribute.frameworks then
            for _, framework in ipairs(attribute.frameworks) do
                ldflags[#ldflags+1] = "-framework"
                ldflags[#ldflags+1] = framework
            end
        end
        target.input = input
        target.ldflags = ldflags
        target.deps = deps
        return
    end

    if deps then
        local mark = {[name] = true}
        local i = 1
        while i <= #deps do
            local dep = deps[i]
            if mark[dep] then
                table.remove(deps, i)
            else
                mark[dep] = true
                local target = context.loaded_targets[dep]
                assert(target ~= nil, ("`%s`: deps `%s` undefine."):format(name, dep))
                if target.deps then
                    tbl_append(deps, target.deps)
                end
                i = i + 1
            end
        end
        for _, dep in ipairs(attribute.deps) do
            local target = context.loaded_targets[dep]
            if target.input then
                tbl_append(input, target.input)
            end
            implicit_input[#implicit_input+1] = target.implicit_input
        end
    end
    assert(#input > 0, ("`%s`: no source files found."):format(name))

    local binname
    update_ldflags(context, ldflags, attribute, name, rootdir)

    local fin_ldflags = table.concat(ldflags, " ")
    if rule == "shared_library" then
        if context.globals.compiler == "emcc" then
            binname = fs.path "$bin" / (name .. ".wasm")
        elseif context.globals.os == "windows" then
            binname = fs.path "$bin" / (name .. ".dll")
        else
            binname = fs.path "$bin" / (name .. ".so")
        end
        cc.rule_dll(ninja, name, fin_ldflags)
        if context.globals.compiler == 'msvc' then
            local lib = fs.path '$bin' / (name..".lib")
            target.input = {lib}
            target.implicit_input = binname
            ninja:build(binname, input, {
                implicit_inputs = implicit_input,
                implicit_outputs = lib,
            })
        else
            if context.globals.os == "windows" then
                target.input = {binname}
            else
                target.implicit_input = binname
            end
            ninja:build(binname, input, {
                implicit_inputs = implicit_input,
            })
        end
    elseif rule == "executable" then
        if context.globals.compiler == "emcc" then
            binname = fs.path "$bin" / (name .. ".js")
        elseif context.globals.os == "windows" then
            binname = fs.path "$bin" / (name .. ".exe")
        else
            binname = fs.path "$bin" / name
        end
        target.implicit_input = binname
        cc.rule_exe(ninja, name, fin_ldflags)
        ninja:build(binname, input, {
            implicit_inputs = implicit_input,
        })
    elseif rule == "static_library" then
        if context.globals.os == "windows" then
            binname = fs.path("$bin") / (name .. ".lib")
        else
            binname = fs.path("$bin") / ("lib"..name .. ".a")
        end
        target.input = {binname}
        cc.rule_lib(ninja, name)
        ninja:build(binname, input, {
            implicit_inputs = implicit_input,
        })
    end
    ninja:phony(name, binname)
end

local GEN = {}

local NAMEIDX = 0
local function generateTargetName()
    NAMEIDX = NAMEIDX + 1
    return ("__target_0x%08x__"):format(NAMEIDX)
end

local function addImplicitInput(context, implicit_input, name, dep)
    local target = context.loaded_targets[dep]
    assert(target ~= nil, ("`%s`: deps `%s` undefine."):format(name, dep))
    if target.input then
        tbl_append(implicit_input, target.input)
    end
    implicit_input[#implicit_input+1] = target.implicit_input
end

local function getImplicitInput(context, name, attribute)
    local implicit_input = {}
    if attribute.deps then
        for _, dep in ipairs(attribute.deps) do
            addImplicitInput(context, implicit_input, name, dep)
        end
    end
    return implicit_input
end

function GEN.default(context, attribute)
    local ninja = context.ninja
    local targets = {}
    if type(attribute) == "table" then
        for _, dep in ipairs(attribute) do
            if dep then
                addImplicitInput(context, targets, 'default', dep)
            end
        end
    elseif type(attribute) == "string" then
        local dep = attribute
        addImplicitInput(context, targets, 'default', dep)
    end
    ninja:default(targets)
end

function GEN.phony(context, name, attribute)
    local ninja = context.ninja
    local workdir = fs.path(init_single(attribute, 'workdir', '.'))
    local rootdir = (workdir / init_single(attribute, 'rootdir', '.')):lexically_normal()
    local input = attribute.input or {}
    local output = attribute.output or {}
    local implicit_input = getImplicitInput(context, name, attribute)
    for i = 1, #input do
        input[i] = fmtpath_v3(context, rootdir, input[i])
    end
    for i = 1, #output do
        output[i] = fmtpath_v3(context, rootdir, output[i])
    end
    if name then
        if #output == 0 then
            ninja:phony(name, input, {
                implicit_inputs = implicit_input,
            })
        else
            ninja:phony(name, output)
            ninja:phony(output, input, {
                implicit_inputs = implicit_input,
            })
        end
        context.loaded_targets[name] = {
            implicit_input = name,
        }
    else
        if #output == 0 then
            error(("`%s`: no output."):format(name))
        else
            ninja:phony(output, input, {
                implicit_inputs = implicit_input,
            })
        end
    end
end

function GEN.build(context, name, attribute, shell)
    local tmpName = not name
    name = name or generateTargetName()
    assert(context.loaded_targets[name] == nil, ("`%s`: redefinition."):format(name))

    local ninja = context.ninja
    local workdir = fs.path(init_single(attribute, 'workdir', '.'))
    local rootdir = (workdir / init_single(attribute, 'rootdir', '.')):lexically_normal()
    local input = attribute.input or {}
    local output = attribute.output or {}
    local pool =  init_single(attribute, 'pool')
    local implicit_input = getImplicitInput(context, name, attribute)

    for i = 1, #input do
        input[i] = fmtpath_v3(context, rootdir, input[i])
    end
    for i = 1, #output do
        output[i] = fmtpath_v3(context, rootdir, output[i])
    end

    local command = {}
    local function push(v)
        command[#command+1] = fsutil.quotearg(v)
    end
    local function push_command(t)
        for _, v in ipairs(t) do
            if type(v) == 'table' then
                push_command(v)
            elseif type(v) == 'userdata' then
                push(fmtpath_v3(context, rootdir, v))
            elseif type(v) == 'string' then
                if v:sub(1,1) == '@' then
                    push(fmtpath_v3(context, rootdir, v:sub(2)))
                else
                    v = v:gsub("@{([^}]*)}", function (s)
                        return fmtpath_v3(context, rootdir, s)
                    end)
                    push(v)
                end
            end
        end
    end
    push_command(attribute)

    if shell then
        if context.globals.hostshell == "cmd" then
            table.insert(command, 1, "cmd")
            table.insert(command, 2, "/c")
        elseif context.globals.hostos == "windows" then
            local s = {}
            for _, opt in ipairs(command) do
                s[#s+1] = opt
            end
            command = {
                "sh",
                "-e",
                "-c", fsutil.quotearg(table.concat(s, " "))
            }
        else
            local s = {}
            for _, opt in ipairs(command) do
                s[#s+1] = opt
            end
            command = {
                "/bin/sh",
                "-e",
                "-c", fsutil.quotearg(table.concat(s, " "))
            }
        end
    end

    local rule_name = name:gsub("[^%w_]", "_")
    local outname
    if #output == 0 then
        outname = '$builddir/_/' .. rule_name
    else
        outname = output
    end
    ninja:rule('build_'..rule_name, table.concat(command, " "))
    ninja:build(outname, input, {
        implicit_inputs = implicit_input,
        variables = { pool = pool },
    })
    if not tmpName then
        ninja:phony(name, outname)
        context.loaded_targets[name] = {
            implicit_input = name,
        }
    end
end

function GEN.copy(context, name, attribute)
    local ninja = context.ninja
    local workdir = fs.path(init_single(attribute, 'workdir', '.'))
    local rootdir = (workdir / init_single(attribute, 'rootdir', '.')):lexically_normal()
    local input = attribute.input or {}
    local output = attribute.output or {}
    local implicit_input = getImplicitInput(context, name, attribute)

    if context.globals.hostshell == "cmd" then
        ninja:rule('copy', 'cmd /c copy 1>NUL 2>NUL /y $in$input $out', {
            description = 'Copy $in$input $out',
            restat = 1,
        })
    elseif context.globals.hostos == "windows" then
        ninja:rule('copy', 'sh -c "cp -afv $in$input $out 1>/dev/null"', {
            description = 'Copy $in$input $out',
            restat = 1,
        })
    else
        ninja:rule('copy', 'cp -afv $in$input $out 1>/dev/null', {
            description = 'Copy $in$input $out',
            restat = 1,
        })
    end

    for i = 1, #input do
        local v = input[i]
        if type(v) == 'string' and v:sub(1,1) == '@' then
            v =  v:sub(2)
        end
        input[i] = fmtpath_v3(context, rootdir, v)
    end
    for i = 1, #output do
        local v = output[i]
        if type(v) == 'string' and v:sub(1,1) == '@' then
            v =  v:sub(2)
        end
        output[i] = fmtpath_v3(context, rootdir, v)
    end
    assert(#input == #output, ("`%s`: The number of input and output must be the same."):format(name))

    if #implicit_input == 0 then
        for i = 1, #input do
            ninja:build(output[i], input[i])
        end
    else
        for i = 1, #input do
            ninja:build(output[i], nil, {
                implicit_inputs = implicit_input,
                variables = { input = input[i] },
            })
        end
    end

    if name then
        assert(context.loaded_targets[name] == nil, ("`%s`: redefinition."):format(name))
        ninja:phony(name, output)
        context.loaded_targets[name] = {
            implicit_input = name,
        }
    end
end

function GEN.shell(self, name, attribute)
    GEN.build(self, name, attribute, true)
end

function GEN.lua_library(context, name, attribute)
    local lua_library = require "lua_library"
    generate(lua_library(context, name, attribute))
end

local writer = {
    loaded_targets = {}
}
local targets = {}
local scripts = {}
local mark_scripts = {}

function writer:add_target(t)
    targets[#targets+1] = t
end

function writer:add_script(path)
    if mark_scripts[path] then
        return
    end
    mark_scripts[path] = true
    scripts[#scripts+1] = fsutil.relative(path, WORKDIR:string())
end

local function get_luamake(context)
    local proc = arg[-1]
    if proc == "luamake" then
        return "luamake"
    end
    return fmtpath(context, fs.exe_path():string())
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

function writer:generate(force)
    local builddir = WORKDIR / globals.builddir
    local ninja_script = builddir / "build.ninja"
    if not force and fs.exists(ninja_script) then
        return
    end
    local context = self
    cc = require("compiler." .. globals.compiler)
    context.cc = cc
    context.globals = globals
    fs.create_directories(builddir)

    local ninja = require "ninja_writer"(ninja_script:string())

    ninja:variable("builddir", fmtpath(context, globals.builddir))
    ninja:variable("bin", fmtpath(context, globals.bindir))
    ninja:variable("obj", fmtpath(context, globals.objdir))

    context.ninja = ninja

    if globals.compiler == "msvc" then
        if not arguments.args.prebuilt then
            local msvc = require "msvc_util"
            msvc.createEnvConfig(globals.arch, arguments.what == "rebuild")
            ninja:variable("msvc_deps_prefix", msvc.getPrefix())
        end
    else
        assert(globals.compiler=="gcc" or globals.compiler=="clang" or globals.compiler=="emcc")
        local cc = globals.cc or globals.compiler
        if globals.hostshell == 'cmd' then
            cc = 'cmd /c '..cc
        end
        ninja:variable("cc", cc)
    end

    if not arguments.args.prebuilt then
        ninja:variable("luamake", get_luamake(context))
        ninja:rule('configure', '$luamake init ' .. configure_args(), { generator = 1 })
        ninja:build("$builddir/build.ninja", scripts)
    end

    for _, target in ipairs(targets) do
        local rule = target[1]
        local name = target[2]
        local local_attribute = target[3]
        local global_attribute = target[4]
        if rule == "default" then
            GEN.default(context, name)
            goto continue
        end
        local res = reslovePlatformSpecific(global_attribute, local_attribute)
        context.globals = global_attribute
        if GEN[rule] then
            GEN[rule](context, name, res)
        else
            generate(context, rule, name, res)
        end
        ::continue::
    end

    ninja:close()
end

return writer
