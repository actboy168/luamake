local os = require "bee.platform".os

if os == "windows" then
    local function read_registry_key(path, key)
        local f = io.popen(string.format("reg query \"%s\" /v \"%s\"", path, key), "r")
        if f then
            for l in f:lines() do
                local r = l:match "^    [^%s]+    [^%s]+    (.*)$"
                if r then
                    f:close()
                    return r
                end
            end
        end
    end
    local ArchMap <const> = {
        AMD64 = "x86_64",
        ARM64 = "arm64",
        x86 = "x86",
    }
    local PROCESSOR_ARCHITECTURE = read_registry_key([[HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment]], "PROCESSOR_ARCHITECTURE")
    local arch = ArchMap[PROCESSOR_ARCHITECTURE]
    if not arch then
        error("Cannot detect architecture")
    end
    return arch
end
