local clang = require 'compiler.gcc'
clang.name = "clang"

function clang.mode(_, mode, flags, _)
    if mode == 'debug' then
        flags[#flags+1] = '-g'
    end
end

function clang.rule_dll(w, name, links, ldflags, mode, attribute)
    local STRIP = (mode == 'release') and [[ && strip -u -r -x $out]] or ''
    w:rule('LINK_'..name:gsub('[^%w_]', '_'), ([[gcc -dynamiclib -Wl,-undefined,dynamic_lookup $in -o $out %s %s%s]]):format(ldflags, links, STRIP),
    {
        description = 'Link SharedLibrary $out'
    })
end

function clang.rule_exe(w, name, links, ldflags, mode, attribute)
    local STRIP = (mode == 'release') and [[ && strip -u -r -x $out]] or ''
    w:rule('LINK_'..name:gsub('[^%w_]', '_'), ([[gcc $in -o $out %s %s%s]]):format(ldflags, links, STRIP),
    {
        description = 'Link Executable $out'
    })
end

return clang
