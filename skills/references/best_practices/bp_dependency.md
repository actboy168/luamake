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

## 5. deps 自动传递导出属性（export_includes / export_objdeps）

某些目标（如 `lm:lua_embed`）会通过 `deps` 自动向依赖方导出编译级别的属性，包括头文件搜索路径（`export_includes`）和编译前置依赖（`export_objdeps`）。依赖方只需声明 `deps`，无需手动指定 `includes` 和 `objdeps`。

### 典型场景：依赖 lua_embed 生成的头文件

`lm:lua_embed` 会自动导出两个属性：
- **`export_includes`**：生成的头文件所在目录（含 `lua_embed_data.h`），依赖方自动获得 `-I` 搜索路径
- **`export_objdeps`**：代码生成 phony 目标（聚合 `lua_embed.c` 和 `lua_embed_data.h` 两个输出），确保编译前生成的源码与头文件都已就绪

```lua
lm:lua_embed "my_embed" {
    data = {
        preload = {
            { dir = "scripts" },
        },
        main = {
            { file = "main.lua", name = "main.lua" },
        },
    },
}

-- ✅ 推荐：通过 deps 自动获取 includes 和 objdeps
lm:lua_src "my_glue" {
    deps     = "my_embed",
    includes = "3rd/bee.lua",          -- 只需写自己额外的 includes
    sources  = "src/my_glue.cpp",      -- 该文件 #include <lua_embed_data.h>
}

-- ❌ 不推荐：手动硬编码内部路径和目标名
lm:lua_src "my_glue" {
    includes = {
        "3rd/bee.lua",
        "_build/lua_embed/my_embed",                -- 内部路径，不应硬编码
    },
    sources  = "src/my_glue.cpp",
    objdeps  = "__lua_embed_gen_my_embed__",         -- 内部目标名，不应硬编码
}
```

> **原理**：`lm:lua_embed` 在 `loaded_target` 中设置了 `export_includes` 和 `export_objdeps` 字段。`generate_compile` 在处理 `deps` 时，会自动将这些导出属性合并到依赖方的 `attribute.includes` 和 `attribute.objdeps` 中。这是一个通用机制，未来其他代码生成目标也可以使用。
