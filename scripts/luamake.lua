local fs = require "bee.filesystem"
local platform = require "bee.platform"
local compiler = (function ()
    if platform.OS == "Windows" then
        if os.getenv "MSYSTEM" then
            return "gcc"
        end
        return "cl"
    elseif platform.OS == "Linux" then
        return "gcc"
    elseif platform.OS == "macOS" then
        return "clang"
    end
end)()

local cc = require("compiler." .. compiler)


local builddir = WORKDIR / 'build'
fs.create_directories(builddir)

local ninja = require "common.ninja_syntax"
local w = ninja.Writer((builddir / (ARGUMENTS.f or 'make.lua')):replace_extension(".ninja"):string())
ninja.DEFAULT_LINE_WIDTH = 100

w:variable("builddir", builddir:string())
w:variable("makedir", MAKEDIR:string())
w:variable("bin", "$builddir/bin")
w:variable("obj", "$builddir/obj")

if cc.name == "cl" then
    local msvc = require "common.msvc"
    w:variable("deps_prefix", msvc.prefix)
end

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
local function expand_path(t, path)
    local filename = path:filename():string()
    if filename:find("*", 1, true) == nil then
        accept_path(t, path)
        return
    end
    local pattern = glob_compile(filename)
    for file in path:parent_path():list_directory() do
        if glob_match(pattern, file:filename():string()) then
            accept_path(t, file)
        end
    end
end
local function get_sources(root, sources)
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

local function generate(self, rule, name, attribute)
    assert(self.target[name] == nil, ("`%s`: redefinition."):format(name))
    assert(type(attribute.sources) == "table" and #attribute.sources > 0, ("`%s`: sources cannot be empty."):format(name))
    local rootdir = fs.path(attribute.rootdir or self.rootdir or ".")
    local mode = attribute.mode or self.mode or "release"
    local optimize = attribute.optimize or self.optimize or (mode == "debug" and "none" or "faster")
    local warnings = attribute.warnings or self.warnings or "normal"
    local defines = attribute.defines or self.defines or {}
    local includes = attribute.includes or self.includes or {}
    local links = attribute.links or self.links or {}
    local linkdirs = attribute.linkdirs or self.linkdirs or {}
    local sources = get_sources(rootdir, attribute.sources)
    local implicit = {}
    local input = {}

    local flags = attribute.flags or self.flags or {}
    local ldflags = attribute.ldflags or self.ldflags or {}

    tbl_append(flags, cc.flags)
    tbl_append(ldflags, cc.ldflags)

    flags[#flags+1] = cc.optimize[optimize]
    flags[#flags+1] = cc.warnings[warnings]

    cc.mode(name, mode, flags, ldflags)

    for _, inc in ipairs(includes) do
        flags[#flags+1] = cc.includedir(rootdir / inc)
    end

    for _, macro in ipairs(defines) do
        flags[#flags+1] = cc.define(macro)
    end

    if cc.name == "gcc" and rule == "shared_library" and platform.OS ~= "Windows" then
        flags[#flags+1] = "-fPIC"
    end

    if attribute.deps then
        local linkbin = false
        for _, dep in ipairs(attribute.deps) do
            local depsTarget = self.target[dep]
            assert(depsTarget ~= nil, ("`%s`: can`t find deps `%s`"):format(name, dep))

            flags[#flags+1] = cc.includedir(depsTarget.rootdir)
            if depsTarget.rule == "shared_library" then
                if not linkbin then
                    linkbin = true
                    linkdirs[#linkdirs+1] = fs.path("$bin")
                end
                links[#links+1] = fs.path(depsTarget.name):replace_extension(""):string()
            end
            implicit[#implicit+1] = fs.path("$bin") / depsTarget.name
        end
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

    local tbl_links = {}
    for _, link in ipairs(links) do
        tbl_links[#tbl_links+1] = cc.link(link)
    end
    for _, linkdir in ipairs(linkdirs) do
        ldflags[#ldflags+1] = cc.linkdir(linkdir)
    end
    local fin_links = table.concat(tbl_links, " ")
    local fin_ldflags = table.concat(ldflags, " ")

    local outname = name
    if rule == "executable" then
        if platform.OS == "Windows" then
            outname = name .. ".exe"
        end
    elseif rule == "shared_library" then
        if platform.OS == "Windows" then
            outname = name .. ".dll"
        else
            outname = name .. ".so"
        end
    end
    if rule == "shared_library" then
        cc.rule_dll(w, name, fin_links, fin_ldflags)
    else
        cc.rule_exe(w, name, fin_links, fin_ldflags)
    end
    if attribute.input or self.input then
        tbl_append(input, attribute.input or self.input)
    end
    w:build(fs.path("$bin") / outname, "LINK_"..fmtname, input, implicit)
    self.target[name] = {
        rootdir = rootdir,
        name = outname,
        rule = rule,
    }
end

local lm = {}

lm.target = {}
lm.writer = w
lm.cc = cc
LUAMAKE = lm

function lm:shared_library(name)
    return function (attribute)
        generate(self, "shared_library", name, attribute)
    end
end

function lm:executable(name)
    return function (attribute)
        generate(self, "executable", name, attribute)
    end
end

function lm:close()
    local build_lua = ARGUMENTS.f or 'make.lua'
    local build_ninja = (fs.path('$builddir') / build_lua):replace_extension(".ninja")
    w:variable("luamake", arg[-1])
    w:rule('configure', '$luamake init -f $in', { generator = 1 })
    w:build(build_ninja, 'configure', build_lua)
    w:close()
end

function lm:lua_library(name)
    local lua_library = require "common.lua_library"
    return lua_library(name)
end

return lm
