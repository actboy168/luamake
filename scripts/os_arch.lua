local os = require "bee.platform".os

local function shell(command)
    local f = assert(io.popen(command, "r"))
    local r = f:read "l"
    f:close()
    return r
end

if os == "windows" then
    -- https://learn.microsoft.com/en-us/archive/blogs/david.wang/howto-detect-process-bitness
    -- https://learn.microsoft.com/en-us/windows/win32/winprog64/wow64-implementation-details
    local function get_env(name)
        name = "%"..name.."%"
        local value = shell("echo "..name)
        if value == name then
            return ""
        end
        return value
    end
    local function get_env_arch()
        local PROCESSOR_ARCHITEW6432 = get_env "PROCESSOR_ARCHITEW6432"
        if PROCESSOR_ARCHITEW6432 ~= "" then
            return PROCESSOR_ARCHITEW6432
        end
        return get_env "PROCESSOR_ARCHITECTURE"
    end
    local ArchMap <const> = {
        AMD64 = "x86_64",
        ARM64 = "arm64",
        x86 = "x86",
    }
    local arch = ArchMap[get_env_arch()]
    if not arch then
        error("Cannot detect architecture")
    end
    return arch
end
