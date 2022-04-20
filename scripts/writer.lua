local fs = require "bee.filesystem"
local arguments = require "arguments"
local globals = require "globals"
local fsutil = require "fsutil"
local glob = require "glob"
local pathutil = require "pathutil"

local cc

local writer = {loaded={}}
local loaded = writer.loaded
local loaded_rule = {}
local statements = {}
local targets = {}
local scripts = {}
local mark_scripts = {}

local file_type = {
    cxx = "cxx",
    cpp = "cxx",
    cc = "cxx",
    mm = "cxx",
    c = "c",
    m = "c",
    rc = "rc",
    s = "asm",
    def = "raw",
    obj = "raw",
}

local function fmtpath(p)
    return p:gsub('\\', '/')
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

local function get_sources(attribute)
    local sources = attribute.sources
    if type(sources) ~= "table" then
        return {}
    end
    local rootdir = attribute.rootdir
    local result = glob(rootdir, sources)
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
        table.insert(t, pos+i-1, a[i])
    end
end

local PlatformAttribute <const> = 0
local PlatformPath      <const> = 1
local PlatformArgs      <const> = 2

local ATTRIBUTE <const> = {
    -- os
    windows  = PlatformAttribute,
    linux    = PlatformAttribute,
    macos    = PlatformAttribute,
    ios      = PlatformAttribute,
    android  = PlatformAttribute,
    -- cc
    msvc     = PlatformAttribute,
    gcc      = PlatformAttribute,
    clang    = PlatformAttribute,
    mingw    = PlatformAttribute,
    emcc     = PlatformAttribute,
    -- path
    includes = PlatformPath,
    linkdirs = PlatformPath,
    input    = PlatformPath,
    output   = PlatformPath,
    script   = PlatformPath,
    -- other
    args     = PlatformArgs,
}

local function push_string(t, a)
    if type(a) == 'string' then
        t[#t+1] = a
    elseif type(a) == 'userdata' then
        t[#t+1] = a
    elseif type(a) == 'table' then
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
    if type(a) == 'string' then
        t[#t+1] = pathutil.tostring(root, a)
    elseif type(a) == 'userdata' then
        t[#t+1] = pathutil.tostring(root, a)
    elseif type(a) == 'table' then
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
    if type(a) == 'string' then
        if a:sub(1,1) == '@' then
            t[#t+1] = pathutil.tostring(root, a:sub(2))
        else
            t[#t+1] = a:gsub("@{([^}]*)}", function (s)
                return pathutil.tostring(root, s)
            end)
        end
    elseif type(a) == 'userdata' then
        t[#t+1] = pathutil.tostring(root, a)
    elseif type(a) == 'table' then
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

local function reslove_table(root, t, a)
    merge_table(root, t, a)
    if a[globals.os] then
        merge_table(root, t, a[globals.os])
    end
    if a[globals.compiler] then
        merge_table(root, t, a[globals.compiler])
    end
    if a.mingw and globals.os == "windows" and globals.compiler == "gcc" then
        merge_table(root, t, a.mingw)
    end
end

local function normalize_rootdir(workdir, rootdir)
    if type(rootdir) == 'table' then
        if getmetatable(rootdir) == nil then
            rootdir = rootdir[#rootdir]
        else
            rootdir = tostring(rootdir)
        end
    end
    return fsutil.normalize(workdir, rootdir or '.')
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

local function update_warnings(flags, warnings)
    if not warnings then
        flags[#flags+1] = cc.warnings["on"]
        return
    end
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

local function update_flags(flags, attribute, name, rule)
    local optimize = init_single(attribute, 'optimize', (attribute.mode == "debug" and "off" or "speed"))
    local defines = attribute.defines or {}

    tbl_append(flags, cc.flags)
    flags[#flags+1] = cc.optimize[optimize]
    update_warnings(flags, attribute.warnings)
    if globals.os ~= "windows" then
        local visibility = init_single(attribute, 'visibility', "hidden")
        if visibility ~= "default" then
            flags[#flags+1] = ('-fvisibility=%s'):format(visibility or 'hidden')
        end
        if rule == "shared_library" then
            flags[#flags+1] = "-fPIC"
        end
    end
    cc.update_flags(flags, attribute, name)

    if attribute.includes then
        for _, inc in ipairs(attribute.includes) do
            flags[#flags+1] = cc.includedir(inc)
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

local function update_ldflags(context, ldflags, attribute, name)
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
            local target = context:load(dep)
            assert(target, ("`%s`: can`t find deps `%s`"):format(name, dep))
            if target.ldflags then
                tbl_append(ldflags, target.ldflags)
            end
        end
    end

    cc.update_ldflags(ldflags, attribute, name)
end

local function generate(context, rule, name, attribute)
    local target = loaded[name]
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
            loaded[name] = target
        end
    end

    local ninja = context.ninja
    local bindir = init_single(attribute, 'bindir', globals.bindir)
    local sources = get_sources(attribute)
    local objargs = attribute.objdeps and {implicit_inputs=attribute.objdeps} or nil
    local implicit_input = {}

    init_single(attribute, 'mode', 'release')
    init_single(attribute, 'crt', 'dynamic')
    init_single(attribute, 'c', '')
    init_single(attribute, 'cxx', '')
    init_single(attribute, 'visibility')
    init_single(attribute, 'target')
    init_single(attribute, 'arch')
    init_single(attribute, 'vendor')
    init_single(attribute, 'sys')
    init_single(attribute, 'luaversion')

    if attribute.luaversion then
        require "lua_support"(context, rule, name, attribute)
    end

    if attribute.deps then
        if deps then
            tbl_append(deps, attribute.deps)
        else
            deps = attribute.deps
        end
    end

    local flags =  {}
    update_flags(flags, attribute, name, rule)

    local fin_flags = table.concat(flags, " ")
    for _, source in ipairs(sources) do
        local ext = fsutil.extension(source):sub(2):lower()
        local type = file_type[ext]
        if type == "raw" then
            input[#input+1] = source
            goto continue
        end
        local objpath = fsutil.join("$obj", name, fsutil.filename(source))
        if type == "c" then
            cc.rule_c(ninja, name, attribute, fin_flags)
            input[#input+1] = ninja:build_obj(objpath, source, objargs)
        elseif type == "cxx" then
            cc.rule_cxx(ninja, name, attribute, fin_flags)
            input[#input+1] = ninja:build_obj(objpath, source, objargs)
        elseif globals.os == "windows" and type == "rc" then
            cc.rule_rc(ninja, name)
            input[#input+1] = ninja:build_obj(objpath, source, objargs)
        elseif type == "asm" then
            if globals.compiler == "msvc" then
                error "TODO"
            end
            cc.rule_asm(ninja, name, fin_flags)
            input[#input+1] = ninja:build_obj(objpath, source, objargs)
        else
            error(("`%s`: unknown file extension: `%s` in `%s`"):format(name, ext, source))
        end
        ::continue::
    end

    if rule == 'source_set' then
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
                local t = context:load(dep)
                assert(t, ("`%s`: deps `%s` undefine."):format(name, dep))
                if t.deps then
                    tbl_insert(deps, i + 1, t.deps)
                end
                i = i + 1
            end
        end
        for _, dep in ipairs(deps) do
            local t = context:load(dep)
            if t.input then
                tbl_append(input, t.input)
            end
            implicit_input[#implicit_input+1] = t.implicit_input
        end
    end
    assert(#input > 0, ("`%s`: no source files found."):format(name))

    local binname
    if bindir == globals.bindir then
        bindir = "$bin"
    end
    update_ldflags(context, ldflags, attribute, name)

    local fin_ldflags = table.concat(ldflags, " ")
    if rule == "shared_library" then
        cc.rule_dll(ninja, name, fin_ldflags)
        if globals.compiler == 'msvc' then
            binname = bindir.."/"..name..".dll"
            local lib = ('$obj/%s/%s.lib'):format(name, name)
            target.input = {lib}
            target.implicit_input = binname
            ninja:build(binname, input, {
                implicit_inputs = implicit_input,
                implicit_outputs = lib,
            })
        elseif globals.os == "windows" then
            binname = bindir.."/"..name..".dll"
            target.input = {binname}
            ninja:build(binname, input, {
                implicit_inputs = implicit_input,
            })
        else
            if globals.compiler == "emcc" then
                binname = bindir.."/"..name..".wasm"
            else
                binname = bindir.."/"..name..".so"
            end
            target.implicit_input = binname
            ninja:build(binname, input, {
                implicit_inputs = implicit_input,
            })
        end
    elseif rule == "executable" then
        if globals.compiler == "emcc" then
            binname = bindir.."/"..name .. ".js"
        elseif globals.os == "windows" then
            binname = bindir.."/"..name .. ".exe"
        else
            binname = bindir.."/"..name
        end
        target.implicit_input = binname
        cc.rule_exe(ninja, name, fin_ldflags)
        ninja:build(binname, input, {
            implicit_inputs = implicit_input,
        })
    elseif rule == "static_library" then
        if globals.os == "windows" then
            binname = bindir.."/"..name ..".lib"
        else
            binname = bindir.."/lib"..name .. ".a"
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
    local target = context:load(dep)
    assert(target, ("`%s`: deps `%s` undefine."):format(name, dep))
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
    local default_targets = {}
    local function add_target(v)
        if type(v) == "table" then
            for _, dep in ipairs(v) do
                if dep then
                    add_target(dep)
                end
            end
        elseif type(v) == "string" then
            local dep = v
            addImplicitInput(context, default_targets, 'default', dep)
        end
    end
    add_target(attribute)
    ninja:default(default_targets)
end

function GEN.phony(context, name, attribute)
    local ninja = context.ninja
    local input = attribute.input or {}
    local output = attribute.output or {}
    local implicit_input = getImplicitInput(context, name, attribute)

    local n = #input
    for i = 1, #implicit_input do
        input[n+i] = implicit_input[i]
    end

    if name then
        if #output == 0 then
            ninja:phony(name, input)
        else
            ninja:phony(name, output)
            for _, out in ipairs(output) do
                ninja:phony(out, input)
            end
        end
        loaded[name] = {
            implicit_input = name,
        }
    else
        if #output == 0 then
            error(("`%s`: no output."):format(name))
        else
            for _, out in ipairs(output) do
                ninja:phony(out, input)
            end
        end
    end
end

function GEN.rule(context, name, local_attribute, global_attribute)
    assert(loaded_rule[name] == nil, ("rule `%s`: redefinition."):format(name))
    loaded_rule[name] = true

    local ninja = context.ninja
    local attribute = reslove_attributes(global_attribute, local_attribute)
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

function GEN.runlua(context, name, attribute)
    local tmpName = not name
    name = name or generateTargetName()
    assert(loaded[name] == nil, ("`%s`: redefinition."):format(name))

    local ninja = context.ninja
    local input = attribute.input or {}
    local output = attribute.output or {}
    local implicit_input = getImplicitInput(context, name, attribute)
    local script = assert(init_single(attribute, 'script'), ("`%s`: need attribute `script`."):format(name))
    implicit_input[#implicit_input+1] = script

    if attribute.args then
        local command = {}
        for i, v in ipairs(attribute.args) do
            command[i] = fsutil.quotearg(v)
        end
        command = table.concat(command, " ")
        ninja:rule('runlua', "$luamake lua $script "..command, {
            description = "lua $script "..command
        })
    else
        ninja:rule('runlua', "$luamake lua $script", {
            description = "lua $script"
        })
    end


    local outname
    if #output == 0 then
        outname = '$builddir/_/' .. name
    else
        outname = output
    end
    ninja:build(outname, input, {
        variables = {
            script = script,
        },
        implicit_inputs = implicit_input,
    })
    if not tmpName then
        ninja:phony(name, outname)
        loaded[name] = {
            implicit_input = name,
        }
    end
end

function GEN.build(context, name, attribute)
    local tmpName = not name
    name = name or generateTargetName()
    assert(loaded[name] == nil, ("`%s`: redefinition."):format(name))

    local ninja = context.ninja
    local input = attribute.input or {}
    local output = attribute.output or {}
    local implicit_input = getImplicitInput(context, name, attribute)
    local rule = init_single(attribute, 'rule')

    if rule then
        assert(loaded_rule[rule], ("unknown rule `%s`"):format(rule))
        ninja:set_rule(rule)
    else
        local command = {}
        for i, v in ipairs(attribute) do
            command[i] = fsutil.quotearg(v)
        end
        ninja:rule('build_'..name, table.concat(command, " "))
    end

    local outname
    if #output == 0 then
        outname = '$builddir/_/' .. name
    else
        outname = output
    end
    ninja:build(outname, input, {
        implicit_inputs = implicit_input,
    })
    if not tmpName then
        ninja:phony(name, outname)
        loaded[name] = {
            implicit_input = name,
        }
    end
end

function GEN.copy(context, name, attribute)
    if loaded[name] ~= nil then
        return
    end
    local ninja = context.ninja
    local input = attribute.input or {}
    local output = attribute.output or {}
    local implicit_input = getImplicitInput(context, name, attribute)

    if globals.hostshell == "cmd" then
        ninja:rule('copy', "powershell -NonInteractive -Command Copy-Item -Path $in$input -Destination $out | Out-Null", {
            description = 'Copy $in$input $out',
            restat = 1,
        })
    elseif globals.hostos == "windows" then
        ninja:rule('copy', 'sh -c "cp -fv $in$input $out 1>/dev/null"', {
            description = 'Copy $in$input $out',
            restat = 1,
        })
    else
        ninja:rule('copy', 'cp -fv $in$input $out 1>/dev/null', {
            description = 'Copy $in$input $out',
            restat = 1,
        })
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
        assert(loaded[name] == nil, ("`%s`: redefinition."):format(name))
        ninja:phony(name, output)
        loaded[name] = {
            implicit_input = name,
        }
    end
end

local function loadtarget(context, target)
    local rule = target[1]
    local name = target[2]
    local local_attribute = target[3]
    local global_attribute = target[4]
    local res = reslove_attributes(global_attribute, local_attribute)
    target.loaded = true
    if GEN[rule] then
        GEN[rule](context, name, res)
    else
        generate(context, rule, name, res)
    end
    if name == nil then
        return false
    end
    if loaded[name] == nil then
        loaded[name] = false
        return false
    end
    return loaded[name]
end

function writer:load(name)
    local r = loaded[name]
    if r ~= nil then
        return r
    end
    local t = targets[name]
    if not t then
        loaded[name] = false
        return false
    end
    return loadtarget(self, t)
end

function writer:has(name)
    return targets[name] ~= nil
end

function writer:add_statement(t)
    statements[#statements+1] = t
end

function writer:add_target(t)
    statements[#statements+1] = t
    local name = t[2]
    if name then
        targets[name] = t
    end
end

function writer:add_script(p)
    if mark_scripts[p] then
        return
    end
    mark_scripts[p] = true
    scripts[#scripts+1] = fsutil.relative(p, WORKDIR)
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

local STATEMENT <const> = {
    default = true,
    rule = true,
}

function writer:generate()
    local builddir = fsutil.join(WORKDIR, globals.builddir)
    local ninja_script = fsutil.join(builddir, "build.ninja")
    local context = self
    cc = require("compiler." .. globals.compiler)
    fs.create_directories(builddir)

    local ninja = require "ninja_writer"(ninja_script)

    ninja:variable("builddir", fmtpath(globals.builddir))
    ninja:variable("bin", fmtpath(globals.bindir))
    ninja:variable("obj", fmtpath(globals.objdir))

    context.ninja = ninja

    if globals.compiler == "msvc" then
        if not globals.prebuilt then
            local msvc = require "msvc_util"
            msvc.createEnvConfig(globals.arch, arguments.what == "rebuild")
            ninja:variable("msvc_deps_prefix", msvc.getPrefix())
        end
    else
        local compiler = globals.cc or globals.compiler
        if globals.hostshell == "cmd" then
            compiler = 'cmd /c '..compiler
        end
        ninja:variable("cc", compiler)
    end

    if globals.prebuilt then
        ninja:variable("luamake", "luamake")
    else
        ninja:variable("luamake", get_luamake())
        ninja:rule('configure', '$luamake init ' .. configure_args(), { generator = 1 })
        ninja:build("$builddir/build.ninja", scripts)
    end

    for _, statement in ipairs(statements) do
        local rule = statement[1]
        if STATEMENT[rule] then
            GEN[rule](context, table.unpack(statement, 2))
        else
            if not statement.loaded then
                loadtarget(context, statement)
            end
        end
    end

    ninja:close()
end

return writer
