local emcc = require 'compiler.gcc'

function emcc.update_ldflags(context, ldflags, attribute)
    ldflags[#ldflags+1] = '-s'
    ldflags[#ldflags+1] = 'WASM=1'
end

function emcc.rule_dll(w, name, ldflags)
    w:rule('link_'..name, ([[$cc $in -o $out -s SIDE_MODULE=1 %s]])
    :format(ldflags),
    {
        description = 'Link    Dll $out'
    })
end

function emcc.rule_exe(w, name, ldflags)
    w:rule('link_'..name, ([[$cc $in -o $out %s]])
    :format(ldflags),
    {
        description = 'Link    Exe $out'
    })
end

return emcc
