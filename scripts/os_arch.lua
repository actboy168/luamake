local os_name = require "bee.platform".os

if os_name == "windows" then
    -- https://learn.microsoft.com/en-us/archive/blogs/david.wang/howto-detect-process-bitness
    -- https://learn.microsoft.com/en-us/windows/win32/winprog64/wow64-implementation-details
    local function env_arch()
        local PROCESSOR_ARCHITEW6432 = os.getenv "PROCESSOR_ARCHITEW6432"
        if PROCESSOR_ARCHITEW6432 ~= nil then
            return PROCESSOR_ARCHITEW6432
        end
        return os.getenv "PROCESSOR_ARCHITECTURE"
    end
    local ArchMap <const> = {
        AMD64 = "x86_64",
        ARM64 = "arm64",
        x86 = "x86",
    }
    local arch = ArchMap[env_arch() or ""]
    if not arch then
        error("Cannot detect architecture")
    end
    return arch
end
