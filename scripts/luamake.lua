local fs = require "bee.filesystem"
local sp = require "bee.subprocess"
local memfile = require "memfile"
local arguments = require "arguments"
local globals = require "globals"

local cc

local function fmtpath(path)
    if globals.hostshell == "cmd" then
        path = path:gsub('/', '\\')
    else
        path = path:gsub('\\', '/')
    end
    return path
end

local function fmtpath_v3(rootdir, path)
    path = fs.path(path)
    if not path:is_absolute() and path:string():sub(1, 1) ~= "$" then
        path = fs.relative(fs.absolute(path, rootdir), WORKDIR)
    end
    return fmtpath(path:string())
end

-- TODO 在某些平台上忽略大小写？
local function glob_compile(pattern)
    return ("^%s$"):format(pattern:gsub("[%^%$%(%)%%%.%[%]%+%-%?]", "%%%0"):gsub("%*", ".*"))
end
local function glob_match(pattern, target)
    return target:match(pattern) ~= nil
end

local function accept_path(t, path)
    assert(fs.exists(path), ("source `%s` is not exists."):format(path:string()))
    local repath = fs.relative(path, WORKDIR):string()
    if t[repath] then
        return
    end
    t[#t+1] = repath
    t[repath] = #t
end
local function expand_dir(t, pattern, dir)
    assert(fs.exists(dir), ("source dir `%s` is not exists."):format(dir:string()))
    for file in dir:list_directory() do
        if fs.is_directory(file) then
            expand_dir(t, pattern, file)
        else
            if glob_match(pattern, file:filename():string()) then
                accept_path(t, file)
            end
        end
    end
end
local function expand_path(t, path)
    local filename = path:filename():string()
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

local function get_warnings(warnings)
    local error = nil
    local level = 'on'
    for _, warn in ipairs(warnings) do
        if warn == 'error' then
            error = true
        else
            level = warn
        end
    end
    return {error = error, level = level}
end

local function merge_attribute(from, to)
    if type(from) == 'string' then
        to[#to+1] = from
    elseif type(from) == 'userdata' then
        to[#to+1] = from
    elseif type(from) == 'table' then
        for _, e in ipairs(from) do
            merge_attribute(e, to)
        end
    end
    return to
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

local function update_flags(flags, attribute, instance, name, rootdir, rule)
    local optimize = init_single(attribute, 'optimize', (attribute.mode == "debug" and "off" or "speed"))
    local warnings = get_warnings(attribute.warnings or {})
    local defines = attribute.defines or {}

    tbl_append(flags, cc.flags)
    flags[#flags+1] = cc.optimize[optimize]
    flags[#flags+1] = cc.warnings[warnings.level]
    if warnings.error then
        flags[#flags+1] = cc.warnings.error
    end
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
            flags[#flags+1] = cc.includedir(fmtpath_v3(rootdir, inc))
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

local function update_ldflags(ldflags, attribute, instance, name, rootdir)
    tbl_append(ldflags, cc.ldflags)
    cc.update_ldflags(ldflags, attribute)

    if attribute.links then
        for _, link in ipairs(attribute.links) do
            ldflags[#ldflags+1] = cc.link(link)
        end
    end
    if attribute.linkdirs then
        for _, linkdir in ipairs(attribute.linkdirs) do
            ldflags[#ldflags+1] = cc.linkdir(fmtpath_v3(rootdir, linkdir))
        end
    end
    if attribute.ldflags then
        tbl_append(ldflags, attribute.ldflags)
    end

    if attribute.deps then
        for _, dep in ipairs(attribute.deps) do
            local target = instance._targets[dep]
            assert(target ~= nil, ("`%s`: can`t find deps `%s`"):format(name, dep))
            if target.ldflags then
                tbl_append(ldflags, target.ldflags)
            end
        end
    end
end

local function generate(self, rule, name, attribute)
    assert(self._targets[name] == nil, ("`%s`: redefinition."):format(name))

    local ninja = self.ninja
    local workdir = fs.path(init_single(attribute, 'workdir', '.'))
    local rootdir = fs.absolute(fs.path(init_single(attribute, 'rootdir', '.')), workdir)
    local sources = get_sources(rootdir, attribute.sources)
    local implicit_input = {}
    local input = {}

    init_single(attribute, 'mode', 'release')
    init_single(attribute, 'crt', 'dynamic')
    init_single(attribute, 'c', "c89")
    init_single(attribute, 'cxx', "c++17")
    init_single(attribute, 'visibility')
    init_single(attribute, 'target')
    init_single(attribute, 'arch')
    init_single(attribute, 'vendor')
    init_single(attribute, 'sys')

    local flags =  {}
    update_flags(flags, attribute, self, name, rootdir, rule)

    local fin_flags = table.concat(flags, " ")
    local fmtname = name:gsub("[^%w_]", "_")
    local has_c = false
    local has_cxx = false
    local has_rc = false
    local has_asm = false
    for _, source in ipairs(sources) do
        local objname = fs.path("$obj") / name / fs.path(source):filename():replace_extension(".obj")
        input[#input+1] = objname
        local ext = fs.path(source):extension():string():sub(2):lower()
        local type = file_type[ext]
        if type == "c" then
            if not has_c then
                has_c = true
                cc.rule_c(ninja, name, attribute, fin_flags)
            end
            ninja:build(objname, "C_"..fmtname, source)
        elseif type == "cxx" then
            if not has_cxx then
                has_cxx = true
                cc.rule_cxx(ninja, name, attribute, fin_flags)
            end
            ninja:build(objname, "CXX_"..fmtname, source)
        elseif globals.os == "windows" and type == "rc" then
            if not has_rc then
                cc.rule_rc(ninja, name)
            end
            ninja:build(objname, "RC_"..fmtname, source)
        elseif type == "asm" then
            if globals.compiler == "msvc" then
                error "TODO"
            end
            if not has_asm then
                has_asm = true
                cc.rule_asm(ninja, name, fin_flags)
            end
            ninja:build(objname, "ASM_"..fmtname, source)
        else
            error(("`%s`: unknown file extension: `%s` in `%s`"):format(name, ext, source))
        end
    end

    local t = {
    }
    self._targets[name] = t

    if rule == 'source_set' then
        local dep_ldflags = {}
        if attribute.links then
            for _, link in ipairs(attribute.links) do
                dep_ldflags[#dep_ldflags+1] = cc.link(link)
            end
        end
        if attribute.linkdirs then
            for _, linkdir in ipairs(attribute.linkdirs) do
                dep_ldflags[#dep_ldflags+1] = cc.linkdir(fmtpath_v3(rootdir, linkdir))
            end
        end
        if attribute.ldflags then
            tbl_append(dep_ldflags, attribute.ldflags)
        end
        if globals.compiler == "clang" and attribute.frameworks then
            for _, framework in ipairs(attribute.frameworks) do
                dep_ldflags[#dep_ldflags+1] = "-framework"
                dep_ldflags[#dep_ldflags+1] = framework
            end
        end
        t.input = input
        t.ldflags = dep_ldflags
        t.deps = attribute.deps
        return
    end

    if attribute.deps then
        local deps = attribute.deps
        local mark = {[name] = true}
        local i = 1
        while i <= #deps do
            local dep = deps[i]
            if mark[dep] then
                table.remove(deps, i)
            else
                mark[dep] = true
                local target = self._targets[dep]
                if target.deps then
                    tbl_append(deps, target.deps)
                end
                i = i + 1
            end
        end
        for _, dep in ipairs(attribute.deps) do
            local target = self._targets[dep]
            if target.input then
                tbl_append(input, target.input)
            end
            implicit_input[#implicit_input+1] = target.implicit_input
        end
    end
    assert(#input > 0, ("`%s`: no source files found."):format(name))

    local binname
    local ldflags =  {}
    update_ldflags(ldflags, attribute, self, name, rootdir)

    local fin_ldflags = table.concat(ldflags, " ")
    if rule == "shared_library" then
        if globals.os == "windows" then
            binname = fs.path "$bin" / (name .. ".dll")
        else
            binname = fs.path "$bin" / (name .. ".so")
        end
        cc.rule_dll(ninja, name, fin_ldflags)
        if globals.compiler == 'msvc' then
            local lib = fs.path '$bin' / (name..".lib")
            t.input = {lib}
            t.implicit_input = binname
            ninja:build(binname, "LINK_"..fmtname, input, implicit_input, nil, nil, lib)
        else
            if globals.os == "windows" then
                t.input = {binname}
            else
                t.implicit_input = binname
            end
            ninja:build(binname, "LINK_"..fmtname, input, implicit_input)
        end
    elseif rule == "executable" then
        if globals.os == "windows" then
            binname = fs.path("$bin") / (name .. ".exe")
        else
            binname = fs.path("$bin") / name
        end
        t.implicit_input = binname
        cc.rule_exe(ninja, name, fin_ldflags)
        ninja:build(binname, "LINK_"..fmtname, input, implicit_input)
    elseif rule == "static_library" then
        if globals.os == "windows" then
            binname = fs.path("$bin") / (name .. ".lib")
        else
            binname = fs.path("$bin") / ("lib"..name .. ".a")
        end
        t.input = {binname}
        cc.rule_lib(ninja, name)
        ninja:build(binname, "LINK_"..fmtname, input, implicit_input)
    end
    ninja:build(name, 'phony', binname)
end

local GEN = {}

local ruleCopy = false

local NAMEIDX = 0
local function generateTargetName()
    NAMEIDX = NAMEIDX + 1
    return ("__target_0x%08x__"):format(NAMEIDX)
end

local function addImplicitInput(self, implicit_input, name)
    local target = self._targets[name]
    assert(target ~= nil, ("`%s`: undefine."):format(name))
    if target.input then
        tbl_append(implicit_input, target.input)
    end
    implicit_input[#implicit_input+1] = target.implicit_input
end

local function getImplicitInput(self, attribute)
    local implicit_input = {}
    if attribute.deps then
        for _, dep in ipairs(attribute.deps) do
            addImplicitInput(self, implicit_input, dep)
        end
    end
    return implicit_input
end

function GEN.default(self, attribute)
    local ninja = self.ninja
    local targets = {}
    if type(attribute) == "table" then
        for _, name in ipairs(attribute) do
            if name then
                addImplicitInput(self, targets, name)
            end
        end
    elseif type(attribute) == "string" then
        local name = attribute
        addImplicitInput(self, targets, name)
    end
    ninja:default(targets)
end

function GEN.phony(self, name, attribute)
    local ninja = self.ninja
    local workdir = fs.path(init_single(attribute, 'workdir', '.'))
    local rootdir = fs.absolute(fs.path(init_single(attribute, 'rootdir', '.')), workdir)
    local input = attribute.input or {}
    local output = attribute.output or {}
    local implicit_input = getImplicitInput(self, attribute)
    for i = 1, #input do
        input[i] = fmtpath_v3(rootdir, input[i])
    end
    for i = 1, #output do
        output[i] = fmtpath_v3(rootdir, output[i])
    end
    if name then
        if #output == 0 then
            ninja:build(name, 'phony', input, implicit_input)
        else
            ninja:build(name, 'phony', output)
            ninja:build(output, 'phony', input, implicit_input)
        end
        self._targets[name] = {
            implicit_input = name,
        }
    else
        if #output == 0 then
            error(("`%s`: no output."):format(name))
        else
            ninja:build(output, 'phony', input, implicit_input)
        end
    end
end

function GEN.build(self, name, attribute, shell)
    local tmpName = not name
    name = name or generateTargetName()
    assert(self._targets[name] == nil, ("`%s`: redefinition."):format(name))

    local ninja = self.ninja
    local workdir = fs.path(init_single(attribute, 'workdir', '.'))
    local rootdir = fs.absolute(fs.path(init_single(attribute, 'rootdir', '.')), workdir)
    local input = attribute.input or {}
    local output = attribute.output or {}
    local pool =  init_single(attribute, 'pool')
    local implicit_input = getImplicitInput(self, attribute)

    for i = 1, #input do
        input[i] = fmtpath_v3(rootdir, input[i])
    end
    for i = 1, #output do
        output[i] = fmtpath_v3(rootdir, output[i])
    end

    local command = {}
    local function push(v)
        command[#command+1] = sp.quotearg(v)
    end
    local function push_command(t)
        for _, v in ipairs(t) do
            if type(v) == 'table' then
                push_command(v)
            elseif type(v) == 'userdata' then
                push(fmtpath_v3(rootdir, v))
            elseif type(v) == 'string' then
                if v:sub(1,1) == '@' then
                    push(fmtpath_v3(rootdir, v:sub(2)))
                else
                    v = v:gsub("@{([^}]*)}", function (s)
                        return fmtpath_v3(rootdir, s)
                    end)
                    push(v)
                end
            end
        end
    end
    push_command(attribute)

    if shell then
        if globals.hostshell == "cmd" then
            table.insert(command, 1, "cmd")
            table.insert(command, 2, "/c")
        elseif globals.hostos == "windows" then
            local s = {}
            for _, opt in ipairs(command) do
                s[#s+1] = opt
            end
            command = {
                "sh",
                "-e",
                "-c", sp.quotearg(table.concat(s, " "))
            }
        else
            local s = {}
            for _, opt in ipairs(command) do
                s[#s+1] = opt
            end
            command = {
                "/bin/sh",
                "-e",
                "-c", sp.quotearg(table.concat(s, " "))
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
    ninja:build(outname, 'build_'..rule_name, input, implicit_input, nil, {
        pool = pool,
    })
    if not tmpName then
        ninja:build(name, 'phony', outname)
        self._targets[name] = {
            implicit_input = name,
        }
    end
end

function GEN.copy(self, name, attribute)
    local ninja = self.ninja
    local workdir = fs.path(init_single(attribute, 'workdir', '.'))
    local rootdir = fs.absolute(fs.path(init_single(attribute, 'rootdir', '.')), workdir)
    local input = attribute.input or {}
    local output = attribute.output or {}
    local implicit_input = getImplicitInput(self, attribute)

    if not ruleCopy then
        ruleCopy = true
        if globals.hostshell == "cmd" then
            ninja:rule('copy', 'cmd /c copy 1>NUL 2>NUL /y $in$input $out', {
                description = 'Copy $in$input $out',
                restat = 1,
            })
        elseif globals.hostos == "windows" then
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
    end
    for i = 1, #input do
        local v = input[i]
        if type(v) == 'string' and v:sub(1,1) == '@' then
            v =  v:sub(2)
        end
        input[i] = fmtpath_v3(rootdir, v)
    end
    for i = 1, #output do
        local v = output[i]
        if type(v) == 'string' and v:sub(1,1) == '@' then
            v =  v:sub(2)
        end
        output[i] = fmtpath_v3(rootdir, v)
    end
    assert(#input == #output, ("`%s`: The number of input and output must be the same."):format(name))

    if #implicit_input == 0 then
        for i = 1, #input do
            ninja:build(output[i], 'copy', input[i])
        end
    else
        for i = 1, #input do
            ninja:build(output[i], 'copy', nil, implicit_input, nil, { input = input[i] })
        end
    end

    if name then
        assert(self._targets[name] == nil, ("`%s`: redefinition."):format(name))
        ninja:build(name, 'phony', output)
        self._targets[name] = {
            implicit_input = name,
        }
    end
end

function GEN.shell(self, name, attribute)
    GEN.build(self, name, attribute, true)
end

function GEN.lua_library(self, name, attribute)
    local lua_library = require "lua_library"
    generate(lua_library(self, name, attribute))
end

local lm = {}

lm._scripts = {}
lm._targets = {}
function lm:add_script(filename)
    if fs.path(filename:sub(1, #(MAKEDIR:string()))) == MAKEDIR then
        return
    end
    filename = fs.relative(fs.path(filename), WORKDIR):string()
    if self._scripts[filename] then
        return
    end
    self._scripts[filename] = true
    self._scripts[#self._scripts+1] = filename
end

local function getexe()
    return fs.exe_path():string()
end

local function pushTable(t, b)
    if type(b) == 'string' then
        t[#t+1] = b
    elseif type(b) == 'userdata' then
        t[#t+1] = b
    elseif type(b) == 'table' then
        if b[1] == nil then
            for k, e in pairs(b) do
                if t[k] == nil then
                    t[k] = {}
                end
                pushTable(t[k], e)
            end
        else
            for _, e in ipairs(b) do
                pushTable(t, e)
            end
        end
    end
    return t
end

local function mergeTable(a, b)
    for k, v in pairs(b) do
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
    return a
end

function lm:finish()
    local builddir = WORKDIR / globals.builddir
    cc = require("compiler." .. globals.compiler)
    self.cc = cc
    fs.create_directories(builddir)

    local ninja_syntax = require "ninja_syntax"
    local ninja_script = (builddir / "build.ninja"):string()
    local ninja = ninja_syntax.Writer(assert(memfile(ninja_script)))

    ninja:variable("builddir", fmtpath(globals.builddir))
    ninja:variable("bin", fmtpath(globals.bindir))
    ninja:variable("obj", fmtpath(globals.objdir))
    if not arguments.args.prebuilt then
        ninja:variable("luamake", fmtpath(getexe()))
    end

    self.ninja = ninja

    if globals.compiler == "msvc" then
        if not arguments.args.prebuilt then
            local msvc = require "msvc_util"
            msvc.createEnvConfig(globals.arch, arguments.what == "rebuild")
            ninja:variable("msvc_deps_prefix", msvc.getPrefix())
        end
    elseif globals.compiler == "gcc"  then
        ninja:variable("cc", globals.cc or "gcc")
    elseif globals.compiler == "clang" then
        ninja:variable("cc", globals.cc or "clang")
    end

    if not arguments.args.prebuilt then
        ninja:rule('configure', '$luamake init', { generator = 1 })
        ninja:build(fs.path '$builddir' / "build.ninja", 'configure', nil, self._scripts)
    end

    for _, target in ipairs(self._export_targets) do
        local rule, name, attribute = target[1], target[2], target[3]
        if rule == "default" then
            GEN.default(self, name)
            goto continue
        end
        local res = {}
        mergeTable(res, globals)
        mergeTable(res, attribute)
        if res[globals.os] then
            mergeTable(res, res[globals.os])
        end
        if res[globals.compiler] then
            mergeTable(res, res[globals.compiler])
        end
        if GEN[rule] then
            GEN[rule](self, name, res)
        else
            generate(self, rule, name, res)
        end
        ::continue::
    end

    ninja:close()
end

return lm
