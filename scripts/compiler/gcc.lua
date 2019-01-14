local fs = require "bee.filesystem"

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
        ['c++latest'] = '-std=c++latest',
    },
    c = {
        ['c89'] = '',
        ['c99'] = '-std=c99',
        ['c11'] = '-std=c11',
    },
    define = function (macro)
        return "-D" .. macro
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

function gcc.mode(_, mode, flags, ldflags)
    if mode == 'debug' then
        flags[#flags+1] = '-g'
    else
        ldflags[#ldflags+1] = '-s'
    end
end

function gcc.rule_c(w, name, flags, cflags)
    w:rule('C_'..name:gsub('[^%w_]', '_'), ([[gcc -MMD -MT $out -MF $out.d %s %s -o $out -c $in]]):format(cflags, flags),
    {
        description = 'Compile C $out',
        deps = 'gcc',
        depfile = '$out.d'
    })
end

function gcc.rule_cxx(w, name, flags, cxxflags)
    w:rule('CXX_'..name:gsub('[^%w_]', '_'), ([[g++ -MMD -MT $out -MF $out.d %s %s -o $out -c $in]]):format(cxxflags, flags),
    {
        description = 'Compile CXX $out',
        deps = 'gcc',
        depfile = '$out.d'
    })
end

function gcc.rule_dll(w, name, links, ldflags, _)
    w:rule('LINK_'..name:gsub('[^%w_]', '_'), ([[gcc --shared $in -o $out %s %s]]):format(ldflags, links),
    {
        description = 'Link SharedLibrary $out'
    })
end

function gcc.rule_exe(w, name, links, ldflags, _)
    w:rule('LINK_'..name:gsub('[^%w_]', '_'), ([[gcc $in -o $out %s %s]]):format(ldflags, links),
    {
        description = 'Link Executable $out'
    })
end

return gcc
