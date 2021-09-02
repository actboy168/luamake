local emcc = require 'compiler.gcc'

function emcc.rule_exe(w, name, ldflags)
    w:rule('LINK_'..name:gsub('[^%w_]', '_'), ([[$cc $in -o $out -s WASM=1 %s]])
    :format(ldflags),
    {
        description = 'Link    Exe $out'
    })
end

return emcc
