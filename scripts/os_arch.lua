local os = require "bee.platform".os

local function shell(command)
    local f = assert(io.popen(command, "r"))
    local r = f:read "l"
    f:close()
    return r
end

if os == "windows" then
    local function get_env(name)
        name = "%"..name.."%"
        local value = shell("echo "..name)
        if value == name then
            return ""
        end
        return value
    end
    local ArchMap <const> = {
        AMD64 = "x86_64",
        ARM64 = "arm64",
        x86 = "x86",
    }
    local arch = ArchMap[get_env "PROCESSOR_ARCHITECTURE"]
    if not arch then
        error("Cannot detect architecture")
    end
    return arch
end
