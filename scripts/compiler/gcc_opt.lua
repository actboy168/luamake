local globals = require "globals"
local log = require "log"

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
        off      = "",
        size     = "-Os",
        speed    = "-O2",
        maxspeed = "-O3",
    },
    warnings = {
        off    = "-w",
        on     = "-Wall",
        all    = "-Wall -Wextra",
        error  = "-Wall -Werror",
        strict = "-Wall -Wextra -Werror",
    },
    define = function (macro)
        if macro == "" then
            return
        end
        return "-D"..macro
    end,
    undef = function (macro)
        return "-U"..macro
    end,
    includedir = function (dir)
        return "-I"..format_path(dir)
    end,
    sysincludedir = function (dir)
        return "-isystem "..format_path(dir)
    end,
    link = function (lib)
        return "-l"..lib
    end,
    linkdir = function (dir)
        return "-L"..format_path(dir)
    end,
}

function gcc.get_c(name, v)
    if v == "" then
        return
    end
    local Known = {
        ["clatest"] = "-std=c2x",
        ["gnulatest"] = "-std=gnu2x",
    }
    if Known[v] then
        return Known[v]
    end
    do
        local what = v:match "^c(.*)$"
        if what then
            return "-std=c"..what
        end
    end
    do
        local what = v:match "^gnu(.*)$"
        if what then
            return "-std=gnu"..what
        end
    end
    log.fatal("`%s`: unknown std c: `%s`", name, v)
end

function gcc.get_cxx(name, v)
    if v == "" then
        return
    end
    local Known = {
        ["c++latest"] = "-std=c++2b",
        ["gnu++latest"] = "-std=gnu++2b",
    }
    if Known[v] then
        return Known[v]
    end
    do
        local what = v:match "^c%+%+(.*)$"
        if what then
            return "-std=c++"..what
        end
    end
    do
        local what = v:match "^gnu%+%+(.*)$"
        if what then
            return "-std=gnu++"..what
        end
    end
    log.fatal("`%s`: unknown std c++: `%s`", name, v)
end

function gcc.rule_asm(w, name, flags)
    w:rule("asm_"..name, ([[$cc -MMD -MT $out -MF $out.d %s -o $out -c $in]])
        :format(flags),
        {
            description = "Compile ASM $out",
            deps = "gcc",
            depfile = "$out.d"
        })
end

function gcc.rule_c(w, name, flags, cflags)
    w:rule("c_"..name, ([[$cc -MMD -MT $out -MF $out.d %s %s -o $out -c $in]])
        :format(cflags, flags),
        {
            description = "Compile C   $out",
            deps = "gcc",
            depfile = "$out.d"
        })
end

function gcc.rule_cxx(w, name, flags, cxxflags)
    w:rule("cxx_"..name, ([[$cc -MMD -MT $out -MF $out.d %s %s -o $out -c $in]])
        :format(cxxflags, flags),
        {
            description = "Compile C++ $out",
            deps = "gcc",
            depfile = "$out.d"
        })
end

function gcc.rule_lib(w, name)
    if globals.os == "windows" and globals.hostshell == "sh" then
        -- mingw
        w:rule("link_"..name, [[sh -c "rm -f $out && $ar rcs $out @$out.rsp"]],
            {
                description = "Link    Lib $out",
                rspfile = "$out.rsp",
                rspfile_content = "$in",
            })
    elseif globals.hostshell == "cmd" then
        w:rule("link_"..name, [[cmd /c $ar rcs $out @$out.rsp]],
            {
                description = "Link    Lib $out",
                rspfile = "$out.rsp",
                rspfile_content = "$in_newline",
            })
    else
        w:rule("link_"..name, [[rm -f $out && $ar rcs $out $in]],
            {
                description = "Link    Lib $out"
            })
    end
end

return gcc
