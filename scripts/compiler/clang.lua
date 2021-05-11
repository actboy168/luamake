local clang = require 'compiler.gcc'

function clang.mode(_, mode, crt, flags, ldflags)
    if crt == 'dynamic' then
        --TODO
    end
    if mode == 'debug' then
        flags[#flags+1] = '-g'
    else
        ldflags[#ldflags+1] = '-Wl,-S,-x'
    end
end

function clang.rule_dll(w, name, links, ldflags)
    w:rule('LINK_'..name:gsub('[^%w_]', '_'), ([[$gxx -dynamiclib -Wl,-undefined,dynamic_lookup $in -o $out %s %s]]):format(ldflags, links),
    {
        description = 'Link    Dll $out'
    })
end

function clang.rule_exe(w, name, links, ldflags)
    w:rule('LINK_'..name:gsub('[^%w_]', '_'), ([[$gxx $in -o $out %s %s]]):format(ldflags, links),
    {
        description = 'Link    Exe $out'
    })
end

return clang
