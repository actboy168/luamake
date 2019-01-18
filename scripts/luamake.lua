local fs = require "bee.filesystem"
local platform = require "bee.platform"
local memfile = require "memfile"
local util = require 'util'

local cc = require("compiler." .. util.compiler)

-- TODO 在某些平台上忽略大小写？
local function glob_compile(pattern)
    return ("^%s$"):format(pattern:gsub("[%^%$%(%)%%%.%[%]%+%-%?]", "%%%0"):gsub("%*", ".*"))
end
local function glob_match(pattern, target)
    return target:match(pattern) ~= nil
end

local function accept_path(t, path)
    if t[path:string()] then
        return
    end
    t[#t+1] = path:string()
    t[path:string()] = #t
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

local function generate(self, rule, name, attribute)
    assert(self._targets[name] == nil, ("`%s`: redefinition."):format(name))

    local function init(attr_name, default)
        local result = attribute[attr_name] or default or {}
        if type(result) == 'string' then
            return {result}
        end
        return result
    end

    local w = self.writer
    local rootdir = fs.path(init('rootdir', '.')[1])
    local sources = get_sources(rootdir, name, init('sources'))
    local mode = init('mode', 'release')[1]
    local optimize = init('optimize', (mode == "debug" and "off" or "speed"))[1]
    local warnings = get_warnings(init('warnings'))
    local defines = init('defines')
    local includes = init('includes')
    local links = init('links')
    local linkdirs = init('linkdirs')
    local flags =  init('flags')
    local ldflags =  init('ldflags')
    local deps =  init('deps')
    local implicit = {}
    local input = {}

    tbl_append(flags, cc.flags)
    tbl_append(ldflags, cc.ldflags)

    flags[#flags+1] = cc.optimize[optimize]
    flags[#flags+1] = cc.warnings[warnings.level]
    if warnings.error then
        flags[#flags+1] = cc.warnings.error
    end

    if cc.name == 'cl' then
        ldflags[#ldflags+1] = "/MACHINE:" .. self.arch
    end

    cc.mode(name, mode, flags, ldflags)

    for _, inc in ipairs(includes) do
        flags[#flags+1] = cc.includedir(rootdir / inc)
    end

    for _, macro in ipairs(defines) do
        flags[#flags+1] = cc.define(macro)
    end

    if rule == "shared_library" and platform.OS ~= "Windows" then
        flags[#flags+1] = "-fPIC"
    end

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
                cc.rule_c(w, name, fin_flags, cflags)
            end
            w:build(objname, "C_"..fmtname, source)
        elseif type == "cxx" then
            if not has_cxx then
                has_cxx = true
                local cxx = attribute.cxx or self.cxx or "c++17"
                local cxxflags = assert(cc.cxx[cxx], ("`%s`: unknown std c++: `%s`"):format(name, cxx))
                cc.rule_cxx(w, name, fin_flags, cxxflags)
            end
            w:build(objname, "CXX_"..fmtname, source)
        else
            error(("`%s`: unknown file extension: `%s`"):format(name, ext))
        end
    end

    for _, dep in ipairs(deps) do
        local depsTarget = self._targets[dep]
        assert(depsTarget ~= nil, ("`%s`: can`t find deps `%s`"):format(name, dep))

        if depsTarget.includedir then
            flags[#flags+1] = cc.includedir(depsTarget.includedir)
        end
        if depsTarget.output then
            input[#input+1] = depsTarget.output
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

    local outname = fs.path("$bin") /name
    if rule == "executable" then
        if platform.OS == "Windows" then
            outname = fs.path("$bin") / (name .. ".exe")
        end
    elseif rule == "shared_library" then
        if platform.OS == "Windows" then
            outname = fs.path("$bin") / (name .. ".dll")
        else
            outname = fs.path("$bin") / (name .. ".so")
        end
    end

    if attribute.input or self.input then
        tbl_append(input, attribute.input or self.input)
    end

    local t = {
        includedir = rootdir,
        outname = outname,
        rule = rule,
    }

    implicit[#implicit+1] = util.script(true)

    if rule == "shared_library" then
        cc.rule_dll(w, name, fin_links, fin_ldflags, mode)
        if cc.name == 'cl' then
            local lib = (fs.path('$bin') / name):replace_extension(".lib")
            t.output = lib
            w:build(outname, "LINK_"..fmtname, input, implicit, nil, nil, lib)
        else
            if platform.OS == "Windows" then
                t.output = outname
            end
            w:build(outname, "LINK_"..fmtname, input, implicit)
        end
    else
        cc.rule_exe(w, name, fin_links, fin_ldflags, mode)
        w:build(outname, "LINK_"..fmtname, input, implicit)
    end
    self._targets[name] = t
end

local GEN = {}

local ruleCommand = false

function GEN.build(self, name, attribute)
    assert(self._targets[name] == nil, ("`%s`: redefinition."):format(name))
    local function init(attr_name, default)
        local result = attribute[attr_name] or default or {}
        if type(result) == 'string' then
            return {result}
        end
        return result
    end
    local w = self.writer
    local deps =  init('deps')
    local implicit = {}

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
    implicit[#implicit+1] = util.script(true)
    w:build(outname, 'command', nil, implicit, nil, {
        COMMAND = attribute
    })
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
    if filename == (ARGUMENTS.f or 'make.lua') then
        return
    end
    if self._scripts[filename] then
        return
    end
    self._scripts[filename] = true
    self._scripts[#self._scripts+1] = filename
end

function lm:finish()
    local globals = self._export_globals
    local builddir = WORKDIR / 'build'
    local bindir = globals.bindir and fs.absolute(fs.path(globals.bindir)):string() or "$builddir/bin"
    local objdir = globals.objdir and fs.absolute(fs.path(globals.objdir)):string() or "$builddir/obj"
    fs.create_directories(builddir)

    local ninja = require "ninja_syntax"
    local ninja_script = util.script():string()
    local w = ninja.Writer(assert(memfile(ninja_script)))
    ninja.DEFAULT_LINE_WIDTH = 100

    w:variable("makedir", MAKEDIR:string())
    w:variable("builddir", builddir:string())
    w:variable("luamake", platform.OS == "Windows" and '$makedir/luamake.exe' or '$makedir/luamake')
    w:variable("bin", bindir)
    w:variable("obj", objdir)

    self.writer = w

    if cc.name == "cl" then
        self.arch = globals.arch or "x86"
        self.winsdk = globals.winsdk
        local msvc = require "msvc"
        msvc:init(self.arch, self.winsdk)
        w:variable("deps_prefix", msvc.prefix)
    end

    for _, target in ipairs(self._export_targets) do
        if GEN[target[1]] then
            GEN[target[1]](self, target[2], target[3])
        else
            generate(self, target[1], target[2], target[3])
        end
    end
    local build_lua = ARGUMENTS.f or 'make.lua'
    local build_ninja = util.script(true)
    w:rule('configure', '$luamake init -f $in', { generator = 1 })
    w:build(build_ninja, 'configure', build_lua, self._scripts)
    w:close()
end

function lm:export()
    if self._export then
        return self._export
    end
    local t = {}
    local globals = {}
    local function setter(_, k, v)
        globals[k] = v
    end
    local function getter(_, k)
        return globals[k]
    end
    local function accept(type, name, attribute)
        for k, v in pairs(globals) do
            if not attribute[k] then
                attribute[k] = v
            end
        end
        t[#t+1] = {type, name, attribute}
    end
    local m = setmetatable({}, {__index = getter, __newindex = setter})
    function m:shared_library(name)
        return function (attribute)
            accept('shared_library', name, attribute)
        end
    end
    function m:executable(name)
        return function (attribute)
            accept('executable', name, attribute)
        end
    end
    function m:lua_library(name)
        return function (attribute)
            accept('lua_library', name, attribute)
        end
    end
    function m:build(name)
        return function (attribute)
            accept('build', name, attribute)
        end
    end
    m.plat = util.plat
    self._export = m
    self._export_targets = t
    self._export_globals = globals
    return m
end

return lm
