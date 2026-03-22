# 最佳实践 - 依赖管理

## 1. deps 依赖的目标必须先定义

`deps` 引用的目标必须在当前目标之前已经定义，否则构建时会报错 `deps "xxx" undefine`。

```lua
-- ✅ 正确：先定义依赖目标，再引用
lm:source_set "core" {
    sources = "core/*.cpp",
}

lm:exe "app" {
    deps = "core",        -- core 已经定义，可以引用
    sources = "main.cpp",
}

-- ❌ 错误：引用尚未定义的目标
lm:exe "app" {
    deps = "core",        -- 此时 core 还未定义，会报错
    sources = "main.cpp",
}

lm:source_set "core" {
    sources = "core/*.cpp",
}
```

> **注意**：使用 `lm:import` 加载子模块时，也需要确保被依赖的目标在 import 的文件中已先被定义。合理安排 `import` 顺序可以避免此问题。

## 2. 源码集复用

```lua
-- 定义可复用的源码集
lm:source_set "core" {
    includes = "include",
    sources = "core/*.cpp",
}

lm:source_set "util" {
    sources = "util/*.cpp",
}

-- 多个目标共享源码
lm:dll "plugin1" {
    deps = { "core", "util" },
    sources = "plugin1/*.cpp",
}

lm:dll "plugin2" {
    deps = { "core", "util" },
    sources = "plugin2/*.cpp",
}
```

## 3. 增量源码集

同名目标多次调用会**累积**源码（bee.lua 核心模式）：

```lua
-- 第一次：基础源码
lm:source_set "lib" {
    sources = "core/*.cpp",
    includes = "include",
}

-- 第二次：添加第三方库
lm:source_set "lib" {
    sources = "3rd/fmt/format.cc",
}

-- 第三次：添加平台特定源码
lm:source_set "lib" {
    sources = "platform/*.cpp",
    windows = { sources = need "win" },
    linux = { sources = need { "linux", "posix" } },
}

-- 第四次：添加绑定代码
lm:source_set "lib" {
    defines = "ENABLE_BINDINGS",
    sources = "bindings/*.cpp",
}
```

## 4. 动态模块发现

```lua
local fs = require "bee.filesystem"
local modules = {}

for path in fs.pairs("modules") do
    if fs.exists(path / "make.lua") then
        local name = path:stem():string()
        lm:import(("modules/%s/make.lua"):format(name))
        if lm:has(name) then
            modules[#modules + 1] = name
        end
    end
end

lm:exe "main" {
    deps = modules,
    sources = "main.cpp",
}
```
