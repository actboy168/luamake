local globals = require 'globals'

local function format_path(path)
    if path:match " " then
        return '"'..path..'"'
    end
    return path
end

local gcc = {
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
        all = "-Wall -Wextra",
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
        return "-I" .. format_path(dir)
    end,
    link = function (lib)
        return "-l" .. lib
    end,
    linkdir = function (dir)
        return "-L" .. format_path(dir)
    end,
    disable_warning = function (w)
        return "-Wno-" .. w
    end
}

function gcc.update_flags(context, flags, attribute)
    if attribute.mode == 'debug' then
        flags[#flags+1] = '-g'
    end
end

function gcc.update_ldflags(context, ldflags, attribute)
    if globals.os == "android" then
        --TODO android不支持static crt
        ldflags[#ldflags+1] = "-lstdc++"
    elseif attribute.crt == "dynamic" then
        ldflags[#ldflags+1] = "-lstdc++"
    else
        ldflags[#ldflags+1] = "-Wl,-Bstatic"
        ldflags[#ldflags+1] = "-lstdc++"
        ldflags[#ldflags+1] = "-Wl,-Bdynamic"
        ldflags[#ldflags+1] = "-static-libgcc"
    end
    if attribute.mode == 'release' then
        ldflags[#ldflags+1] = '-s'
    end
end

function gcc.rule_asm(w, name, flags)
    w:rule('asm_'..name, ([[$cc -MMD -MT $out -MF $out.d %s -o $out -c $in]])
    :format(flags),
    {
        description = 'Compile ASM $out',
        deps = 'gcc',
        depfile = '$out.d'
    })
end

function gcc.rule_c(w, name, attribute, flags)
    local cflags = assert(gcc.c[attribute.c], ("`%s`: unknown std c: `%s`"):format(name, attribute.c))
    w:rule('c_'..name, ([[$cc -MMD -MT $out -MF $out.d %s %s -o $out -c $in]])
    :format(cflags, flags),
    {
        description = 'Compile C   $out',
        deps = 'gcc',
        depfile = '$out.d'
    })
end

function gcc.rule_cxx(w, name, attribute, flags)
    local cxxflags = assert(gcc.cxx[attribute.cxx], ("`%s`: unknown std c++: `%s`"):format(name, attribute.cxx))
    w:rule('cxx_'..name, ([[$cc -MMD -MT $out -MF $out.d %s %s -o $out -c $in]])
    :format(cxxflags, flags),
    {
        description = 'Compile C++ $out',
        deps = 'gcc',
        depfile = '$out.d'
    })
end

function gcc.rule_dll(w, name, ldflags)
    w:rule('link_'..name, ([[$cc --shared $in -o $out %s]])
    :format(ldflags),
    {
        description = 'Link    Dll $out'
    })
end

function gcc.rule_exe(w, name, ldflags)
    w:rule('link_'..name, ([[$cc $in -o $out %s]])
    :format(ldflags),
    {
        description = 'Link    Exe $out'
    })
end

function gcc.rule_lib(w, name)
    w:rule('link_'..name, [[rm -f $out && ar rcs $out $in]],
    {
        description = 'Link    Lib $out'
    })
end

-- mingw only
function gcc.rule_rc(w, name)
    w:rule('rc_'..name, [[windres -i $in -o $out]],
    {
        description = 'Compile Res $out',
    })
end

return gcc
