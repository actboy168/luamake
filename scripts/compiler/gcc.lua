local gcc = {
    name = "gcc",
    flags = {
    },
    ldflags = {
    },
    optimize = {
        off      = '',
        size     = '-Os',
        speed    = '-O2',
        maxspeed = '-O3',
    },
    warnings = {
        off = "-w",
        on  = "-Wall",
        all = "-Wall",
        error = "-Werror",
    },
    cxx = {
        ['c++11'] = '-std=c++11',
        ['c++14'] = '-std=c++14',
        ['c++17'] = '-std=c++17',
        ['c++20'] = '-std=c++20',
        ['c++latest'] = '-std=c++2a',
    },
    c = {
        ['c89'] = '',
        ['c99'] = '-std=c99',
        ['c11'] = '-std=c11',
        ['c17'] = '-std=c17',
    },
    define = function (macro)
        return "-D" .. macro
    end,
    undef = function (macro)
        return "-U" .. macro
    end,
    includedir = function (dir)
        return "-I" .. dir:string()
    end,
    link = function (lib)
        return "-l" .. lib
    end,
    linkdir = function (dir)
        return "-L" .. dir:string()
    end
}

function gcc.mode(_, mode, crt, flags, ldflags)
    if crt ~= 'dynamic' then
        ldflags[#ldflags+1] = "-static"
    end
    if mode == 'debug' then
        flags[#flags+1] = '-g'
    else
        ldflags[#ldflags+1] = '-s'
    end
end

function gcc.rule_c(w, name, flags, cflags, attribute)
    w:rule('C_'..name:gsub('[^%w_]', '_'), ([[%s -MMD -MT $out -MF $out.d %s %s -o $out -c $in]])
    :format(attribute.gcc and attribute.gcc or 'gcc', cflags, flags),
    {
        description = 'Compile C   $out',
        deps = 'gcc',
        depfile = '$out.d'
    })
end

function gcc.rule_cxx(w, name, flags, cxxflags, attribute)
    w:rule('CXX_'..name:gsub('[^%w_]', '_'), ([[%s -MMD -MT $out -MF $out.d %s %s -o $out -c $in]])
    :format(attribute.gxx and attribute.gxx or 'g++', cxxflags, flags),
    {
        description = 'Compile C++ $out',
        deps = 'gcc',
        depfile = '$out.d'
    })
end

function gcc.rule_dll(w, name, links, ldflags, _, attribute)
    w:rule('LINK_'..name:gsub('[^%w_]', '_'), ([[%s --shared $in -o $out %s %s]])
    :format(attribute.gcc and attribute.gcc or 'gcc', ldflags, links),
    {
        description = 'Link    Dll $out'
    })
end

function gcc.rule_exe(w, name, links, ldflags, _, attribute)
    w:rule('LINK_'..name:gsub('[^%w_]', '_'), ([[%s $in -o $out %s %s]])
    :format(attribute.gcc and attribute.gcc or 'gcc', ldflags, links),
    {
        description = 'Link    Exe $out'
    })
end

return gcc
