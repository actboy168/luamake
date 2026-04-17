# 最佳实践 - 代码生成与 objdeps

## 1. 代码生成管道

```lua
-- 步骤1: 生成配置头
lm:runlua "gen_config" {
    script = "gen_config.lua",
    inputs = "config.json",
    outputs = "$builddir/config.h",
}

-- 步骤2: 生成协议代码
lm:build "protocol_gen" {
    deps = "protoc",
    args = { "$bin/protoc", "--cpp_out=$builddir", "$in" },
    inputs = "protocol.proto",
    outputs = { "$builddir/protocol.pb.h", "$builddir/protocol.pb.cc" },
}

-- 步骤3: 依赖生成的文件
lm:exe "app" {
    deps = { "gen_config", "protocol_gen" },
    includes = "$builddir",
    sources = { "main.cpp", "$builddir/protocol.pb.cc" },
}
```

## 2. objdeps 用法

使用脚本动态生成的代码（如头文件、源文件），需要通过 `objdeps` 声明依赖，确保生成的文件在编译前已就绪。

`objdeps` 与 `deps` 的区别：
- `deps` 是**链接级别**依赖，确保依赖目标的产物参与链接。
- `objdeps` 是**编译级别**依赖，确保在编译源文件之前，指定的目标已经完成（例如已生成头文件）。

### 典型场景：依赖生成的头文件

```lua
-- 步骤1: 用脚本生成头文件
lm:runlua "gen_config" {
    script = "gen_config.lua",
    inputs = "config.json",
    outputs = "$builddir/config.h",
}

-- 步骤2: 源文件 #include 了生成的头文件，需要 objdeps 保证编译顺序
lm:exe "app" {
    includes = "$builddir",
    sources = "src/*.cpp",
    objdeps = "gen_config",  -- 编译前先完成 gen_config
}
```

### 典型场景：依赖自定义构建规则生成的代码

```lua
lm:build "gen_protocol" {
    deps = "protoc",
    args = { "$bin/protoc", "--cpp_out=$builddir", "$in" },
    inputs = "protocol.proto",
    outputs = { "$builddir/protocol.pb.h", "$builddir/protocol.pb.cc" },
}

lm:exe "server" {
    includes = "$builddir",
    sources = { "src/*.cpp", "$builddir/protocol.pb.cc" },
    objdeps = "gen_protocol",  -- 编译前先生成协议代码
}
```

> **注意**：如果源文件 `#include` 了动态生成的头文件，但没有声明 `objdeps`，可能导致编译时找不到头文件而失败。

## 3. 使用 lm:lua_embed 嵌入 Lua 资源

当需要将 Lua 脚本或数据文件嵌入到 C/C++ 可执行文件中时，推荐使用 `lm:lua_embed`。它封装了完整的代码生成管道：自动扫描文件 → 生成 C 源码（`lua_embed.c`）与头文件（`lua_embed_data.h`）→ 构建 source_set → 自动导出 `includes` / `objdeps`。相比手动 `lm:runlua` + `objdeps` 更简洁、可靠。

默认嵌入 Lua **源码**（跨 Lua 版本兼容）；需要体积更小或隐藏源码时，在组内设置 `bytecode = true` 嵌入字节码（此时要求 luamake 宿主 Lua 版本与目标 `luaversion` 一致）。

### 最常见形态

```lua
-- 场景 A：不用 bee_glue，自己决定怎么用数据
lm:lua_embed "embedded_lua" {
    data = {
        preload = {
            -- 无 bee_glue 时，preload 组要显式写 pattern 才能得到模块名作键
            { dir = "scripts/modules", pattern = "?.lua;?/init.lua" },
            { file = "scripts/config.lua", name = "config" },
        },
        main = {
            "scripts/main.lua",
        },
    },
}

-- 场景 B：bee.lua 集成（自动 _PRELOAD / main 入口 / require "bee.embed"）
lm:lua_embed "bee_app" {
    bee_glue = true,
    data = {
        preload = { bytecode = true, { dir = "scripts" } },   -- bee_glue 下 preload 自动 lua_mode
        main    = { bytecode = true, "src/main.lua" },
        data    = {},
    },
}

-- 依赖方：只写 deps，不要重复指定 includes / objdeps
lm:lua_exe "myapp" {
    deps    = "bee_app",
    sources = "src/main.cpp",   -- 该文件可 #include "lua_embed_data.h"
}
```

### 关键要点

- **组（group）** 组织：`data` 下每个 string key 是一个组，组名直接成为生成的 `lua_embed_bundle` 结构体字段；
- **`bytecode`** 是每个组独立的开关，默认 `false`；
- **`lua_mode` 启用**：组内任一 `dir` 带 `pattern` → 整组切到 Lua 模块名扫描；`bee_glue = true` 时 `preload` 组自动切到该模式；
- **`bee_glue = true`** 硬约定：必须定义 `main` / `preload` / `data` 三组（可空表 `{}`）；
- 自动导出 `export_includes`（含 `lua_embed_data.h`）与 `export_objdeps`（聚合 `.c` 和 `.h` 两个产物的 phony），**依赖方只需 `deps = "xxx"`**。

> **完整规则（`pattern` 语法、字节码版本约束、模块名冲突处理、bee.embed 运行时契约、不启用 `bee_glue` 时的三种接入姿势、C API、C 标识符碰撞等）请参阅** [`references/advanced/lua_embed.md`](../advanced/lua_embed.md)。

> 与手动 `lm:runlua` 的对比：`lm:lua_embed` 自动处理 Ninja 依赖追踪、`objdeps` 声明、`.c` 与 `lua_embed_data.h` 联合产出等细节；简单的单文件代码生成可继续用 `lm:runlua`，批量嵌入 Lua 资源时优先 `lm:lua_embed`。
