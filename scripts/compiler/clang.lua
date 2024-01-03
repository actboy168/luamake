local clang = require "compiler.gcc"
local globals = require "globals"

local function shell(command)
    local f = assert(io.popen(command, "r"))
    local r = f:read "l"
    f:close()
    return r
end

local function update_target(flags, attribute)
    local target = attribute.target
    if not target then
        local arch = attribute.arch
        local vendor = attribute.vendor
        local sys = attribute.sys
        if not arch and not vendor and not sys then
            return
        end
        if not vendor then
            if sys and sys:match "^macos.+" then
                flags[#flags+1] = sys:gsub("^macos(.*)$", "-mmacosx-version-min=%1")
                if arch then
                    attribute.__arch = arch
                end
                return
            end
            if sys and sys:match "^ios.+" then
                flags[#flags+1] = sys:gsub("^ios(.*)$", "-miphoneos-version-min=%1")
                if arch then
                    attribute.__arch = arch
                end
                return
            end
            if not sys and arch then
                attribute.__arch = arch
                return
            end
        end
        if globals.os == "macos" then
            arch = arch or shell "uname -m"
            vendor = vendor or "apple"
            sys = sys or "darwin"
            target = ("%s-%s-%s"):format(arch, vendor, sys)
        elseif globals.os == "linux" then
            arch = arch or shell "uname -m"
            vendor = vendor or "pc"
            sys = sys or "linux-gnu"
            target = ("%s-%s-%s"):format(arch, vendor, sys)
        elseif globals.os == "android" then
            arch = arch or "aarch64"
            vendor = vendor or "linux"
            sys = sys or "android33"
            target = ("%s-%s-%s"):format(arch, vendor, sys)
        elseif globals.os == "emscripten" then
            arch = arch or "wasm32"
            vendor = vendor or "unknown"
            sys = sys or "emscripten"
            target = ("%s-%s-%s"):format(arch, vendor, sys)
        end
    end
    attribute.__target = target
end

function clang.update_flags(flags, _, cxxflags, attribute)
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
    update_target(flags, attribute)
    if attribute.__target then
        flags[#flags+1] = "-target"
        flags[#flags+1] = attribute.__target
    elseif attribute.__arch then
        flags[#flags+1] = "-arch"
        flags[#flags+1] = attribute.__arch
    end
    if globals.os == "ios" then
        attribute.__isysroot = shell "xcrun --sdk iphoneos --show-sdk-path"
    end
    if attribute.__isysroot then
        flags[#flags+1] = "-isysroot"
        flags[#flags+1] = attribute.__isysroot
    end
end

function clang.update_ldflags(ldflags, attribute)
    if attribute.frameworks then
        for _, framework in ipairs(attribute.frameworks) do
            ldflags[#ldflags+1] = "-framework"
            ldflags[#ldflags+1] = framework
        end
    end
    if attribute.crt == "dynamic" then
        ldflags[#ldflags+1] = "-lstdc++"
    else
        ldflags[#ldflags+1] = "-Wl,--push-state,-Bstatic"
        ldflags[#ldflags+1] = "-lstdc++"
        ldflags[#ldflags+1] = "-Wl,--pop-state"
    end
    if attribute.mode ~= "debug" then
        ldflags[#ldflags+1] = "-Wl,-S,-x"
    end
    if attribute.lto ~= "off" then
        if attribute.lto == "thin" then
            ldflags[#ldflags+1] = "-flto=thin"
        else
            ldflags[#ldflags+1] = "-flto"
        end
    end
    if attribute.__target then
        ldflags[#ldflags+1] = "-target"
        ldflags[#ldflags+1] = attribute.__target
    elseif attribute.__arch then
        ldflags[#ldflags+1] = "-arch"
        ldflags[#ldflags+1] = attribute.__arch
    end
    if attribute.__isysroot then
        ldflags[#ldflags+1] = "-isysroot"
        ldflags[#ldflags+1] = attribute.__isysroot
    end
end

function clang.rule_dll(w, name, ldflags)
    if globals.hostshell == "cmd" then
        w:rule("link_"..name, ([[$cc --shared @$out.rsp -o $out %s]]):format(ldflags),
            {
                description = "Link    Dll $out",
                rspfile = "$out.rsp",
                rspfile_content = "$in",
            })
    elseif globals.os == "macos" or globals.os == "ios" then
        w:rule("link_"..name, ([[$cc -dynamiclib -Wl,-undefined,dynamic_lookup $in -o $out %s]]):format(ldflags),
            {
                description = "Link    Dll $out"
            })
    else
        w:rule("link_"..name, ([[$cc --shared -Wl,-undefined,dynamic_lookup $in -o $out %s]]):format(ldflags),
            {
                description = "Link    Dll $out"
            })
    end
end

function clang.rule_exe(w, name, ldflags)
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

return clang
