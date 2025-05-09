local wasi = require "compiler.gcc_opt"
local globals = require "globals"

function wasi.update_flags(flags, cflags, cxxflags, attribute, name)
    cflags[#cflags+1] = wasi.get_c(name, attribute.c)
    cxxflags[#cxxflags+1] = wasi.get_cxx(name, attribute.cxx)

    if attribute.mode == "debug" then
        flags[#flags+1] = "-g"
    end
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
    flags[#flags+1] = "-target"
    flags[#flags+1] = attribute.target or "wasm32-wasi"
    flags[#flags+1] = "--sysroot"
    flags[#flags+1] = globals.WASI_SDK_PATH.."/share/wasi-sysroot"
end

function wasi.update_ldflags(ldflags, attribute)
    if attribute.crt == "dynamic" then
        ldflags[#ldflags+1] = "-lstdc++"
    else
        ldflags[#ldflags+1] = "-Wl,--push-state,-Bstatic"
        ldflags[#ldflags+1] = "-lstdc++"
        ldflags[#ldflags+1] = "-Wl,--pop-state"
    end
    if attribute.mode ~= "debug" then
        ldflags[#ldflags+1] = "-Wl,-S"
    end
    if attribute.lto ~= "off" then
        if attribute.lto == "thin" then
            ldflags[#ldflags+1] = "-flto=thin"
        else
            ldflags[#ldflags+1] = "-flto"
        end
    end
    ldflags[#ldflags+1] = "-target"
    ldflags[#ldflags+1] = attribute.target or "wasm32-wasi"
    ldflags[#ldflags+1] = "--sysroot"
    ldflags[#ldflags+1] = globals.WASI_SDK_PATH.."/share/wasi-sysroot"
end

function wasi.rule_exe(w, name, ldflags)
    if globals.hostshell == "cmd" then
        w:rule("link_"..name, ([[$cc @$out.rsp -o $out %s]]):format(ldflags),
            {
                description = "Link    Exe $out",
                rspfile = "$out.rsp",
                rspfile_content = "$in",
            })
    else
        w:rule("link_"..name, ([[$cc $in -o $out %s]]):format(ldflags),
            {
                description = "Link    Exe $out"
            })
    end
end

return wasi
