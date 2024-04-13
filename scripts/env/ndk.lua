local globals = require "globals"
local log = require "log"
local fs = require "bee.filesystem"

local function parse_version(str)
    local version = {}
    str:gsub("%d+", function (w) version[#version+1] = tonumber(w) end)
    return version
end

local function compare_version(a, b)
    for i = 1, #a do
        if a[i] > b[i] then
            return 1
        end
        if a[i] < b[i] then
            return -1
        end
    end
    return 0
end

local function find_ndk()
    if globals.hostos == "windows" then
        local LocalAppData = os.getenv "LocalAppData"
        if LocalAppData then
            local rootdir = LocalAppData:gsub("\\", "/").."/Android/Sdk/ndk/"
            if fs.exists(rootdir) then
                local max
                local max_ver
                for path in fs.pairs(rootdir) do
                    local version = path:filename():string()
                    local ver = parse_version(version)
                    if not max_ver or compare_version(ver, max_ver) == 1 then
                        max_ver = ver
                        max = version
                    end
                end
                if max then
                    return rootdir..max.."/"
                end
            end
        end
    end
    log.fastfail "Need to specify NDK path."
end

local HOST_TAG = {
    macos = "darwin-x86_64",
    linux = "linux-x86_64",
    windows = "windows-x86_64",
}

local ndk = globals.ndk or find_ndk()
local path = ndk.."toolchains/llvm/prebuilt/"..HOST_TAG[globals.hostos].."/bin/"
globals.cc = path.."clang"
globals.ar = path.."llvm-ar"
