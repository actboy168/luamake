local emcc = require "compiler.clang"

function emcc.update_flags(flags, _, cxxflags, attribute)
    if attribute.lto ~= "off" then
        if attribute.lto == "thin" then
            flags[#flags+1] = "-flto=thin"
        else
            flags[#flags+1] = "-flto"
        end
    end
    if attribute.rtti == "off" then
        cxxflags[#cxxflags+1] = "-fno-rtti"
    end
    if attribute.mode == "release" then
        flags[#flags+1] = "-g0"
    else
        flags[#flags+1] = "-g3"
    end
end

function emcc.update_ldflags(ldflags, attribute)
    if attribute.lto ~= "off" then
        if attribute.lto == "thin" then
            ldflags[#ldflags+1] = "-flto=thin"
        else
            ldflags[#ldflags+1] = "-flto"
        end
    end
    if attribute.mode == "release" then
        ldflags[#ldflags+1] = "-g0"
    else
        ldflags[#ldflags+1] = "-g3"
    end
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
