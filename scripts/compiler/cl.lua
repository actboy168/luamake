local fs = require "bee.filesystem"

local cl = {
    name = "cl",
    flags = {
        "/EHsc /permissive-",
    },
    ldflags = {
        "/SAFESEH",
    },
    optimize = {
        off      = '/Od',
        size     = '/O1 /GL /Zc:inline',
        speed    = '/O2 /GL /Zc:inline',
        maxspeed = '/Ox /GL /Zc:inline /fp:fast',
    },
    warnings = {
        off = "/W0",
        on  = "/W3",
        all = "/W4",
        error = "/WX",
    },
    cxx = {
        ['c++11'] = '/std:c++11',
        ['c++14'] = '/std:c++14',
        ['c++17'] = '/std:c++17',
        ['c++latest'] = '/std:c++latest',
    },
    c = {
        ['c89'] = '',
        ['c99'] = '/TP',
        ['c11'] = '/TP',
    },
    define = function (macro)
        return "-D" .. macro
    end,
    includedir = function (dir)
        return "-I" .. dir:string()
    end,
    link = function (lib)
        if lib == "stdc++fs" or lib == "stdc++" then
            return
        end
        return lib .. ".lib"
    end,
    linkdir = function (dir)
        return "/libpath:" .. dir:string()
    end
}

function cl.mode(name, mode, flags, ldflags)
    if mode == 'debug' then
        flags[#flags+1] = '/MDd'
        flags[#flags+1] = ('/Zi /FS /Fd%s'):format(fs.path('$obj') / name / "luamake.pdb")
        ldflags[#ldflags+1] = '/DEBUG:FASTLINK'
    else
        flags[#flags+1] = '/MD'
        ldflags[#ldflags+1] = '/DEBUG:NONE'
        ldflags[#ldflags+1] = '/LTCG' -- TODO: msvc2017 has bug for /LTCG:incremental
    end
end

function cl.rule_c(w, name, flags, cflags, attribute)
    w:rule('C_'..name:gsub('[^%w_]', '_'), ([[cl /nologo /showIncludes -c $in /Fo$out %s %s]]):format(flags, cflags),
    {
        description = 'Compile C $out',
        deps = 'msvc',
        msvc_deps_prefix = '$deps_prefix',
    })
end

function cl.rule_cxx(w, name, flags, cxxflags, attribute)
    w:rule('CXX_'..name:gsub('[^%w_]', '_'), ([[cl /nologo /showIncludes -c $in /Fo$out %s %s]]):format(flags, cxxflags),
    {
        description = 'Compile CXX $out',
        deps = 'msvc',
        msvc_deps_prefix = '$deps_prefix',
    })
end

function cl.rule_dll(w, name, links, ldflags, attribute)
    local lib = (fs.path('$bin') / name):replace_extension(".lib")
    w:rule('LINK_'..name:gsub('[^%w_]', '_'), ([[cl /nologo $in %s /link %s /out:$out /DLL /IMPLIB:%s]]):format(links, ldflags, lib),
    {
        description = 'Link SharedLibrary $out'
    })
end

function cl.rule_exe(w, name, links, ldflags, attribute)
    w:rule('LINK_'..name:gsub('[^%w_]', '_'), ([[cl /nologo $in %s /link %s /out:$out]]):format(links, ldflags),
    {
        description = 'Link Executable $out'
    })
end

return cl
