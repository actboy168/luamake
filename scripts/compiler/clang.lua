local clang = require 'compiler.gcc'
local globals = require 'globals'

local function shell(command)
    local f = assert(io.popen(command, 'r'))
    local r = f:read 'l'
    f:close()
    return r
end

local function update_target(context, flags, attribute)
    local target = attribute.target
    if not target then
        assert(globals.hostos ~= "windows")
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
        if globals.hostos == "macos" then
            arch = arch or shell "uname -m"
            vendor = vendor or "apple"
            sys = sys or "darwin"
        else
            arch = arch or shell "uname -m"
            vendor = vendor or "pc"
            sys = sys or "linux-gnu"
        end
        target = ("%s-%s-%s"):format(arch, vendor, sys)
    end
    attribute.__target = target
end

function clang.update_flags(context, flags, attribute)
    if attribute.crt == 'dynamic' then
        --TODO
    end
    if attribute.mode == 'debug' then
        flags[#flags+1] = '-g'
    end
    update_target(context, flags, attribute)
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

function clang.update_ldflags(context, ldflags, attribute)
    if attribute.frameworks then
        for _, framework in ipairs(attribute.frameworks) do
            ldflags[#ldflags+1] = "-framework"
            ldflags[#ldflags+1] = framework
        end
    end
    ldflags[#ldflags+1] = "-lstdc++"
    if attribute.mode == 'release' then
        ldflags[#ldflags+1] = '-Wl,-S,-x'
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
    w:rule('link_'..name, ([[$cc -dynamiclib -Wl,-undefined,dynamic_lookup $in -o $out %s]]):format(ldflags),
    {
        description = 'Link    Dll $out'
    })
end

function clang.rule_exe(w, name, ldflags)
    w:rule('link_'..name, ([[$cc $in -o $out %s]]):format(ldflags),
    {
        description = 'Link    Exe $out'
    })
end

return clang
