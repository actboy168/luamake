# 平台/编译器特定配置

## 平台配置

```lua
lm:exe "myapp" {
    sources = "src/*.cpp",
    
    windows = { links = { "user32", "ws2_32" } },
    linux = { links = { "pthread", "dl" } },
    macos = { frameworks = { "Foundation", "CoreFoundation" } },
    ios = { ldflags = "-fembed-bitcode" },
    android = { links = "log" },
}
```

## 编译器配置

```lua
lm:source_set "core" {
    sources = "core/*.cpp",
    
    msvc = { flags = { "/utf-8", "/W4" } },
    gcc = { flags = { "-fPIC", "-Wall" } },
    clang = { flags = "-Wno-deprecated" } ,
}
```

## 平台特定全局配置

```lua
lm:conf {
    cxx = "c++17",
    macos = {
        flags = "-Wunguarded-availability",
        sys = "macos10.15",  -- 最低版本
    },
}
```

## 平台文件过滤函数

```lua
-- 返回排除不需要平台的 glob 模式
local function need(wanted)
    local exclude = {}
    local all = { "win", "posix", "osx", "linux", "bsd" }
    local map = {}
    if type(wanted) == "table" then
        for _, v in ipairs(wanted) do map[v] = true end
    else
        map[wanted] = true
    end
    for _, plat in ipairs(all) do
        if not map[plat] then
            exclude[#exclude+1] = "!**/*_"..plat..".cpp"
            exclude[#exclude+1] = "!**/"..plat.."/**/*.cpp"
        end
    end
    return exclude
end

lm:source_set "mylib" {
    sources = "src/**/*.cpp",
    windows = { sources = need "win" },
    linux = { sources = need { "linux", "posix" } },
    macos = { sources = need { "osx", "posix" } },
}
```
