local fs = require "bee.filesystem"

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
        "/permissive-",
    },
    ldflags = {
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
        ['c++20'] = '/std:c++latest',
        ['c++latest'] = '/std:c++latest',
    },
    c = {
        ['c89'] = '',
        ['c99'] = '',
        ['c11'] = '/std:c11',
        ['c17'] = '/std:c17',
    },
    define = function (macro)
        return "/D" .. macro
    end,
    undef = function (macro)
        return "/U" .. macro
    end,
    includedir = function (dir)
        return "/I" .. format_path(dir)
    end,
    link = function (lib)
        if lib == "stdc++fs" or lib == "stdc++" then
            return
        end
        return lib .. ".lib"
    end,
    linkdir = function (dir)
        return "/libpath:" .. format_path(dir)
    end,
    disable_warning = function (w)
        return "/wd" .. w
    end
}

function cl.update_flags(context, flags, attribute, name)
    if attribute.mode == 'debug' then
        flags[#flags+1] = attribute.crt == 'dynamic' and '/MDd' or '/MTd'
        flags[#flags+1] = '/FS'
        flags[#flags+1] = '/Zi'
        flags[#flags+1] = ('/Fd$obj/%s/'):format(name)
    else
        flags[#flags+1] = attribute.crt == 'dynamic' and '/MD' or '/MT'
    end
end

function cl.update_ldflags(context, ldflags, attribute, name)
    if attribute.mode == 'debug' then
        ldflags[#ldflags+1] = '/DEBUG'
        ldflags[#ldflags+1] = ('/pdb:$obj/%s.pdb'):format(name)
    else
        ldflags[#ldflags+1] = '/DEBUG:NONE'
        ldflags[#ldflags+1] = '/LTCG' -- TODO: msvc2017 has bug for /LTCG:incremental
    end
end

function cl.rule_c(w, name, attribute, flags)
    local cflags = assert(cl.c[attribute.c], ("`%s`: unknown std c: `%s`"):format(name, attribute.c))
    w:rule('c_'..name, ([[cl /nologo /showIncludes -c $in /Fo$out %s %s]]):format(flags, cflags),
    {
        description = 'Compile C   $out',
        deps = 'msvc',
    })
end

function cl.rule_cxx(w, name, attribute, flags)
    local cxxflags = assert(cl.cxx[attribute.cxx], ("`%s`: unknown std c++: `%s`"):format(name, attribute.cxx))
    w:rule('cxx_'..name, ([[cl /nologo /showIncludes -c $in /Fo$out %s %s]]):format(flags, cxxflags),
    {
        description = 'Compile C++ $out',
        deps = 'msvc',
    })
end

function cl.rule_dll(w, name, ldflags)
    w:rule('link_'..name, ([[cl /nologo $in /link %s /out:$out /DLL /IMPLIB:$obj/%s/%s.lib]]):format(ldflags, name, name),
    {
        description = 'Link    Dll $out',
        restat = 1,
    })
end

function cl.rule_exe(w, name, ldflags)
    w:rule('link_'..name, ([[cl /nologo $in /link %s /out:$out]]):format(ldflags),
    {
        description = 'Link    Exe $out'
    })
end

function cl.rule_lib(w, name)
    w:rule('link_'..name, [[lib /nologo $in /out:$out]],
    {
        description = 'Link    Lib $out'
    })
end

function cl.rule_rc(w, name)
    w:rule('rc_'..name, [[rc /nologo /fo $out $in]],
    {
        description = 'Compile Res $out',
    })
end

return cl
