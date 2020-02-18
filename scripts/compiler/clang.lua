local clang = require 'compiler.gcc'
clang.name = "clang"

function clang.mode(_, mode, crt, flags, ldflags)
    if crt ~= 'dynamic' then
        ldflags[#ldflags+1] = "-static"
    end
    if mode == 'debug' then
        flags[#flags+1] = '-g'
    end
end

function clang.rule_dll(w, name, links, ldflags, mode, _)
    local STRIP = (mode == 'release') and [[ && strip -u -r -x $out]] or ''
    w:rule('LINK_'..name:gsub('[^%w_]', '_'), ([[gcc -dynamiclib -Wl,-undefined,dynamic_lookup $in -o $out %s %s%s]]):format(ldflags, links, STRIP),
    {
        description = 'Link    Dll $out'
    })
end

function clang.rule_exe(w, name, links, ldflags, mode, _)
    local STRIP = (mode == 'release') and [[ && strip -u -r -x $out]] or ''
    w:rule('LINK_'..name:gsub('[^%w_]', '_'), ([[gcc $in -o $out %s %s%s]]):format(ldflags, links, STRIP),
    {
        description = 'Link    Exe $out'
    })
end

return clang
