local platform = require "bee.platform"
if platform.OS == "Windows" then
    if os.getenv "MSYSTEM" then
        return "mingw"
    end
    return "msvc"
elseif platform.OS == "Linux" then
    return "linux"
elseif platform.OS == "macOS" then
    return "macos"
end
