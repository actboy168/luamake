local emcc = require "compiler.clang"

function emcc.update_ldflags()
end

function emcc.rule_dll(w, name, ldflags)
    w:rule("link_"..name, ([[$cc $in -o $out -s SIDE_MODULE=1 %s]])
        :format(ldflags),
        {
            description = "Link    Dll $out"
        })
end

function emcc.rule_exe(w, name, ldflags)
    w:rule("link_"..name, ([[$cc $in -o $out %s]])
        :format(ldflags),
        {
            description = "Link    Exe $out"
        })
end

return emcc
