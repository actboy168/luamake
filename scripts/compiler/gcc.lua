local gcc = require "compiler.gcc_opt"
local globals = require "globals"

function gcc.update_flags(flags, _, cxxflags, attribute, _)
    if attribute.mode == "debug" then
        flags[#flags+1] = "-g"
    end
    if attribute.lto ~= "off" then
        flags[#flags+1] = "-flto"
        flags[#flags+1] = "-fno-fat-lto-objects"
    end
    if attribute.rtti == "off" then
        cxxflags[#cxxflags+1] = "-fno-rtti"
    end
end

function gcc.update_ldflags(ldflags, attribute)
    if attribute.crt == "dynamic" then
        ldflags[#ldflags+1] = "-lstdc++"
    else
        ldflags[#ldflags+1] = "-Wl,-Bstatic"
        ldflags[#ldflags+1] = "-lstdc++"
        ldflags[#ldflags+1] = "-Wl,-Bdynamic"
    end
    if attribute.mode ~= "debug" then
        ldflags[#ldflags+1] = "-s"
    end
    if attribute.lto ~= "off" then
        ldflags[#ldflags+1] = "-flto"
        ldflags[#ldflags+1] = "-fno-fat-lto-objects"
    end
end

function gcc.rule_dll(w, name, ldflags)
    if globals.hostshell == "cmd" then
        w:rule("link_"..name, ([[$cc --shared @$out.rsp -o $out %s]])
            :format(ldflags),
            {
                description = "Link    Dll $out",
                rspfile = "$out.rsp",
                rspfile_content = "$in",
            })
    else
        w:rule("link_"..name, ([[$cc --shared $in -o $out %s]])
            :format(ldflags),
            {
                description = "Link    Dll $out"
            })
    end
end

function gcc.rule_exe(w, name, ldflags)
    if globals.os == "windows" and globals.hostshell == "sh" then
        -- mingw
        w:rule("link_"..name, ([[sh -c "$cc @$out.rsp -o $out %s"]])
            :format(ldflags),
            {
                description = "Link    Exe $out",
                rspfile = "$out.rsp",
                rspfile_content = "$in",
            })
    elseif globals.hostshell == "cmd" then
        w:rule("link_"..name, ([[$cc @$out.rsp -o $out %s]])
            :format(ldflags),
            {
                description = "Link    Exe $out",
                rspfile = "$out.rsp",
                rspfile_content = "$in",
            })
    else
        w:rule("link_"..name, ([[$cc $in -o $out %s]])
            :format(ldflags),
            {
                description = "Link    Exe $out"
            })
    end
end

-- mingw only
function gcc.rule_rc(w, name)
    if globals.os == "windows" and globals.hostshell == "sh" then
        w:rule("rc_"..name, [[windres -i $in -o $out]],
            {
                description = "Compile Res $out",
            })
    end
end

return gcc
