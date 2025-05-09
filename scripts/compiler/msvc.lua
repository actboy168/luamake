local globals = require "globals"
local log = require "log"

local function format_path(path)
    if path:match " " then
        return '"'..path..'"'
    end
    return path
end

local cl = {
    flags = {
        "/EHsc",
        "/Zc:__cplusplus",
    },
    ldflags = {
    },
    optimize = {
        off      = "/Od",
        size     = "/O1 /Zc:inline",
        speed    = "/O2 /Zc:inline",
        maxspeed = "/O2 /Zc:inline /fp:fast",
    },
    warnings = {
        off    = "/W0",
        on     = "/W3",
        all    = "/W4",
        error  = "/W3 /WX",
        strict = "/W4 /WX",
    },
    define = function (macro)
        if macro == "" then
            return
        end
        return "/D"..macro
    end,
    undef = function (macro)
        return "/U"..macro
    end,
    includedir = function (dir)
        return "/I"..format_path(dir)
    end,
    sysincludedir = function (dir)
        return "/I"..format_path(dir)
    end,
    link = function (lib)
        if lib == "stdc++fs" or lib == "stdc++" then
            return
        end
        return lib..".lib"
    end,
    linkdir = function (dir)
        return "/libpath:"..format_path(dir)
    end,
}

local function get_c(name, v)
    if v == "" then
        return
    end
    local Known = {
        ["c89"] = "",
        ["c99"] = "",
        ["c23"] = "/std:clatest",
        ["c2x"] = "/std:clatest",
    }
    if Known[v] then
        return Known[v]
    end
    local what = v:match "^c(.*)$"
    if what then
        return "/std:c"..what
    end
    log.fatal("`%s`: unknown std c: `%s`", name, v)
end

local function get_cxx(name, v)
    if v == "" then
        return
    end
    local Known = {
        ["c++2a"] = "/std:c++20",
        ["c++2b"] = "/std:c++latest",
    }
    if Known[v] then
        return Known[v]
    end
    local what = v:match "^c%+%+(.*)$"
    if what then
        return "/std:c++"..what
    end
    log.fatal("`%s`: unknown std c++: `%s`", name, v)
end

function cl.update_flags(flags, cflags, cxxflags, attribute, name)
    cflags[#cflags+1] = get_c(name, attribute.c)
    cxxflags[#cxxflags+1] = get_cxx(name, attribute.cxx)

    if attribute.permissive == "off" then
        flags[#flags+1] = "/permissive-"
    end
    if attribute.crt == "dynamic" then
        if attribute.optimize == "off" then
            flags[#flags+1] = "/MDd"
        else
            flags[#flags+1] = "/MD"
        end
    else
        if attribute.optimize == "off" then
            flags[#flags+1] = "/MTd"
        else
            flags[#flags+1] = "/MT"
        end
    end
    if attribute.mode == "debug" then
        flags[#flags+1] = "/FS"
        flags[#flags+1] = "/Zi"
        flags[#flags+1] = ("/Fd$obj/%s/"):format(name)
    end
    if globals.cc ~= "clang-cl" and attribute.lto ~= "off" then
        flags[#flags+1] = "/GL"
    end
    if attribute.rtti == "off" then
        cxxflags[#cxxflags+1] = "/GR-"
    end
end

function cl.update_ldflags(ldflags, attribute, name)
    if attribute.mode == "debug" then
        ldflags[#ldflags+1] = "/DEBUG"
        ldflags[#ldflags+1] = ("/pdb:$obj/%s.pdb"):format(name)
    else
        ldflags[#ldflags+1] = "/DEBUG:NONE"
    end
    if attribute.lto ~= "off" then
        ldflags[#ldflags+1] = "/INCREMENTAL:NO"
        if globals.cc ~= "clang-cl" then
            ldflags[#ldflags+1] = "/LTCG" -- TODO: msvc2017 has bug for /LTCG:incremental
        end
    end
end

function cl.rule_asm(w, name, _)
    if globals.arch == "arm64" then
        w:rule("asm_"..name, [[$ml -nologo -o $out $in]],
            {
                description = "Compile ASM $out",
            })
    else
        w:rule("asm_"..name, [[$ml /nologo /quiet /Fo $out /c $in]],
            {
                description = "Compile ASM $out",
            })
    end
end

function cl.rule_c(w, name, flags, cflags)
    w:rule("c_"..name, ([[$cc /nologo /showIncludes -c $in /Fo$out %s %s]]):format(flags, cflags),
        {
            description = "Compile C   $out",
            deps = "msvc",
        })
end

function cl.rule_cxx(w, name, flags, cxxflags)
    w:rule("cxx_"..name, ([[$cc /nologo /showIncludes -c $in /Fo$out %s %s]]):format(flags, cxxflags),
        {
            description = "Compile C++ $out",
            deps = "msvc",
        })
end

function cl.rule_dll(w, name, ldflags)
    w:rule("link_"..name, ([[$cc /nologo @$out.rsp /link %s /out:$out /DLL /IMPLIB:$implib]]):format(ldflags),
        {
            description = "Link    Dll $out",
            rspfile = "$out.rsp",
            rspfile_content = "$in_newline",
            restat = 1,
        })
end

function cl.rule_exe(w, name, ldflags)
    w:rule("link_"..name, ([[$cc /nologo @$out.rsp /link %s /out:$out]]):format(ldflags),
        {
            description = "Link    Exe $out",
            rspfile = "$out.rsp",
            rspfile_content = "$in_newline",
        })
end

function cl.rule_lib(w, name)
    w:rule("link_"..name, [[lib /nologo @$out.rsp /out:$out]],
        {
            description = "Link    Lib $out",
            rspfile = "$out.rsp",
            rspfile_content = "$in_newline",
        })
end

function cl.rule_rc(w, name)
    w:rule("rc_"..name, [[rc /nologo /fo $out $in]],
        {
            description = "Compile Res $out",
        })
end

return cl
