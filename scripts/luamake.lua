local fs = require "bee.filesystem"
local memfile = require "memfile"
local util = require 'util'
local arguments = require "arguments"

local compiler = (function ()
    if arguments.plat == 'mingw' then
        return "gcc"
    elseif arguments.plat == "msvc" then
        return "cl"
    elseif arguments.plat == "linux" then
        return "gcc"
    elseif arguments.plat == "macos" then
        return "clang"
    end
end)()

local cc = require("compiler." .. compiler)

local function f_nil() end

local function isWindows()
    return arguments.plat == "msvc" or arguments.plat == "mingw"
end

local function fmtpath_u(workdir, path)
    return fs.relative(fs.absolute(fs.path(path), workdir), WORKDIR)
end

local function fmtpath(workdir, path)
    local res = fmtpath_u(workdir, path):string()
    if arguments.plat == "msvc" then
        return res:gsub('/', '\\')
    else
        return res:gsub('\\', '/')
    end
end

-- TODO 在某些平台上忽略大小写？
local function glob_compile(pattern)
    return ("^%s$"):format(pattern:gsub("[%^%$%(%)%%%.%[%]%+%-%?]", "%%%0"):gsub("%*", ".*"))
end
local function glob_match(pattern, target)
    return target:match(pattern) ~= nil
end

local function accept_path(t, path)
    local repath = fs.relative(path, WORKDIR):string()
    if t[repath] then
        return
    end
    t[#t+1] = repath
    t[repath] = #t
end
local function expand_dir(t, pattern, dir)
    if not fs.exists(dir) then
        return
    end
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
local function get_sources(root, name, sources)
    assert(type(sources) == "table" and #sources > 0, ("`%s`: sources cannot be empty."):format(name))
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
    for _, e in ipairs(from) do
        if type(e) == 'string' then
            to[#to+1] = e
        elseif type(e) == 'table' then
            merge_attribute(e, to)
        end
    end
    return to
end

local function init_attribute(attribute, attr_name, default)
    if type(default) == 'function' then
        attribute = attribute[attr_name] or default()
    else
        attribute = attribute[attr_name] or default or {}
    end
    if type(attribute) ~= 'table' then
        return {attribute}
    end
    local res = {}
    return merge_attribute(attribute, res)
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

local function generate(self, rule, name, attribute)
    assert(self._targets[name] == nil, ("`%s`: redefinition."):format(name))

    local function init(attr_name, default)
        return init_attribute(attribute, attr_name, default)
    end

    local w = self.writer
    local workdir = fs.path(init('workdir', '.')[1])
    local rootdir = fs.absolute(fs.path(init('rootdir', '.')[1]), workdir)
    local sources = get_sources(rootdir, name, init('sources'))
    local mode = init('mode', 'release')[1]
    local crt = init('crt', 'dynamic')[1]
    local optimize = init('optimize', (mode == "debug" and "off" or "speed"))[1]
    local warnings = get_warnings(init('warnings'))
    local defines = init('defines')
    local undefs = init('undefs')
    local includes = init('includes')
    local links = init('links')
    local linkdirs = init('linkdirs')
    local ud_flags = init('flags')
    local ud_ldflags = init('ldflags')
    local deps =  init('deps')
    local pool =  init('pool', f_nil)[1]
    local implicit = {}
    local input = {}
    assert(#sources > 0, ("`%s`: no source files found."):format(name))

    local flags =  {}
    local ldflags =  {}

    tbl_append(flags, cc.flags)
    tbl_append(ldflags, cc.ldflags)

    flags[#flags+1] = cc.optimize[optimize]
    flags[#flags+1] = cc.warnings[warnings.level]
    if warnings.error then
        flags[#flags+1] = cc.warnings.error
    end

    if cc.name == 'cl' then
        if not attribute.permissive then
            flags[#flags+1] = '/permissive-'
        end
    end

    if arguments.plat == "linux" or arguments.plat == "macos" then
        if attribute.visibility ~= "default" then
            flags[#flags+1] = ('-fvisibility=%s'):format(attribute.visibility or 'hidden')
        end
    end

    cc.mode(name, mode, crt, flags, ldflags)

    for _, inc in ipairs(includes) do
        flags[#flags+1] = cc.includedir(fmtpath_u(workdir, rootdir / inc))
    end

    if mode == "release" then
        defines[#defines+1] = "NDEBUG"
    end

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

    if rule == "shared_library" and not isWindows() then
        flags[#flags+1] = "-fPIC"
    end

    for _, dep in ipairs(deps) do
        local depsTarget = self._targets[dep]
        assert(depsTarget ~= nil, ("`%s`: can`t find deps `%s`"):format(name, dep))
        if depsTarget.includedir then
            flags[#flags+1] = cc.includedir(fmtpath_u(workdir, depsTarget.includedir))
        end
    end

    tbl_append(flags, ud_flags)
    tbl_append(ldflags, ud_ldflags)

    local fin_flags = table.concat(flags, " ")
    local fmtname = name:gsub("[^%w_]", "_")
    local has_c = false
    local has_cxx = false
    for _, source in ipairs(sources) do
        local objname = fs.path("$obj") / name / fs.path(source):filename():replace_extension(".obj")
        input[#input+1] = objname
        local ext = fs.path(source):extension():string():sub(2):lower()
        local type = file_type[ext]
        if type == "c" then
            if not has_c then
                has_c = true
                local c = attribute.c or self.c or "c89"
                local cflags = assert(cc.c[c], ("`%s`: unknown std c: `%s`"):format(name, c))
                cc.rule_c(w, name, fin_flags, cflags, attribute)
            end
            w:build(objname, "C_"..fmtname, source)
        elseif type == "cxx" then
            if not has_cxx then
                has_cxx = true
                local cxx = attribute.cxx or self.cxx or "c++17"
                local cxxflags = assert(cc.cxx[cxx], ("`%s`: unknown std c++: `%s`"):format(name, cxx))
                cc.rule_cxx(w, name, fin_flags, cxxflags, attribute)
            end
            w:build(objname, "CXX_"..fmtname, source)
        else
            error(("`%s`: unknown file extension: `%s`"):format(name, ext))
        end
    end

    local outname
    if rule == "executable" then
        if isWindows() then
            outname = fs.path("$bin") / (name .. ".exe")
        else
            outname = fs.path("$bin") / name
        end
    elseif rule == "shared_library" then
        if isWindows() then
            outname = fs.path("$bin") / (name .. ".dll")
        else
            outname = fs.path("$bin") / (name .. ".so")
        end
    end

    local t = {
        includedir = rootdir,
        outname = outname,
        rule = rule,
    }
    self._targets[name] = t

    if rule == 'source_set' then
        t.output = input
        return
    end

    for _, dep in ipairs(deps) do
        local depsTarget = self._targets[dep]
        if depsTarget.output then
            if type(depsTarget.output) == 'table' then
                tbl_append(input, depsTarget.output)
            else
                input[#input+1] = depsTarget.output
            end
        else
            implicit[#implicit+1] = depsTarget.outname
        end
    end

    local tbl_links = {}
    for _, link in ipairs(links) do
        tbl_links[#tbl_links+1] = cc.link(link)
    end
    for _, linkdir in ipairs(linkdirs) do
        ldflags[#ldflags+1] = cc.linkdir(linkdir)
    end
    local fin_links = table.concat(tbl_links, " ")
    local fin_ldflags = table.concat(ldflags, " ")

    if attribute.input or self.input then
        tbl_append(input, attribute.input or self.input)
    end

    local vars = pool and {pool=pool} or nil
    if rule == "shared_library" then
        cc.rule_dll(w, name, fin_links, fin_ldflags, mode, attribute)
        if cc.name == 'cl' then
            local lib = (fs.path('$bin') / name)..".lib"
            t.output = lib
            w:build(outname, "LINK_"..fmtname, input, implicit, nil, vars, lib)
        else
            if isWindows() then
                t.output = outname
            end
            w:build(outname, "LINK_"..fmtname, input, implicit, nil, vars)
        end
    else
        cc.rule_exe(w, name, fin_links, fin_ldflags, mode, attribute)
        w:build(outname, "LINK_"..fmtname, input, implicit, nil, vars)
    end
end

local GEN = {}

local ruleCommand = false

function GEN.default(self, _, attribute)
    local w = self.writer
    local targets = {}
    for _, name in ipairs(attribute) do
        assert(self._targets[name] ~= nil, ("`%s`: undefine."):format(name))
        targets[#targets+1] = self._targets[name].outname
    end
    w:default(targets)
end

function GEN.phony(self, _, attribute)
    local w = self.writer
    local function init(attr_name, default)
        return init_attribute(attribute, attr_name, default)
    end
    local workdir = fs.path(init('workdir', '.')[1])
    attribute.input  = fmtpath(workdir, attribute.input)
    attribute.output = fmtpath(workdir, attribute.output)
    w:build(attribute.output, 'phony', attribute.input)
end

function GEN.build(self, name, attribute)
    assert(self._targets[name] == nil, ("`%s`: redefinition."):format(name))
    local function init(attr_name, default)
        return init_attribute(attribute, attr_name, default)
    end

    local w = self.writer
    local workdir = fs.path(init('workdir', '.')[1])
    local deps =  init('deps')
    local output =  init('output')
    local pool =  init('pool', f_nil)[1]
    local implicit = {}

    for i = 1, #output do
        output[i] = fmtpath(workdir, output[i])
    end

    for i = 1, #attribute do
        if type(attribute[i]) ~= 'string' then
            attribute[i] = fmtpath(workdir, attribute[i])
        elseif attribute[i]:sub(1,1) == '@' then
            attribute[i] = fmtpath(workdir, attribute[i]:sub(2))
        end
    end

    for _, dep in ipairs(deps) do
        local depsTarget = self._targets[dep]
        assert(depsTarget ~= nil, ("`%s`: can`t find deps `%s`"):format(name, dep))
        implicit[#implicit+1] = depsTarget.outname
    end

    if not ruleCommand then
        ruleCommand = true
        w:rule('command', '$COMMAND', {
            description = '$DESC'
        })
    end
    local outname = '$builddir/_/' .. name:gsub("[^%w_]", "_")
    w:build(outname, 'command', nil, implicit, nil, {
        COMMAND = attribute,
        pool = pool,
    }, output)
    self._targets[name] = {
        outname = outname,
        rule = 'build',
    }
end

function GEN.lua_library(self, name, attribute)
    local lua_library = require "lua_library"
    generate(lua_library(self, name, attribute))
end

local lm = {}

lm._scripts = {}
lm._targets = {}
lm.cc = cc

function lm:add_script(filename)
    if fs.path(filename:sub(1, #(MAKEDIR:string()))) == MAKEDIR then
        return
    end
    filename = fs.relative(fs.path(filename), WORKDIR):string()
    if filename == (arguments.f or 'make.lua') then
        return
    end
    if self._scripts[filename] then
        return
    end
    self._scripts[filename] = true
    self._scripts[#self._scripts+1] = filename
end

local function getexe()
    return fs.exe_path():string()
end

function lm:finish()
    local globals = self._export_globals
    fs.create_directories(WORKDIR / 'build' / arguments.plat)

    local ninja = require "ninja_syntax"
    local ninja_script = util.script():string()
    local w = ninja.Writer(assert(memfile(ninja_script)))
    ninja.DEFAULT_LINE_WIDTH = 100

    w:variable("builddir", ('build/%s'):format(arguments.plat))
    if arguments.rebuilt ~= 'no' then
        w:variable("luamake", getexe())
    end

    if globals.bindir then
        w:variable("bin", globals.bindir)
    else
        w:variable("bin", "$builddir/bin")
    end
    if globals.objdir then
        w:variable("obj", globals.objdir)
    else
        w:variable("obj", "$builddir/obj")
    end

    self.writer = w

    if cc.name == "cl" then
        self.arch = globals.arch
        self.winsdk = globals.winsdk
        local msvc = require "msvc"
        msvc:create_config(self.arch, self.winsdk)

        for _, target in ipairs(self._export_targets) do
            if target[1] ~= 'build' then
                msvc:init(self.arch, self.winsdk)
                if arguments.rebuilt ~= 'no' then
                    self.writer:variable("msvc_deps_prefix", msvc.prefix)
                end
                break
            end
        end
    end

    if arguments.rebuilt ~= 'no' then
        local build_lua = arguments.f or 'make.lua'
        local build_ninja = util.script(true)
        w:rule('configure', '$luamake init -f $in', { generator = 1, restat = 1 })
        w:build(build_ninja, 'configure', build_lua, self._scripts)
    end

    for _, target in ipairs(self._export_targets) do
        if GEN[target[1]] then
            GEN[target[1]](self, target[2], target[3])
        else
            generate(self, target[1], target[2], target[3])
        end
    end
    w:close()
end

return lm
