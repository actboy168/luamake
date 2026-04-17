# 高级 API

SKILL.md 中介绍的是常用的编译目标 API（`lm:exe`、`lm:dll`、`lm:lib` 等）。本文档覆盖 luamake 提供的其他高级 API。

---

## lm:rule — 自定义 Ninja 规则

定义一个自定义的 Ninja 规则，可在 `lm:build` 中引用。等同于 Ninja 的 `rule` 语句。

```lua
lm:rule "gen_header" {
    args = { "$luamake", "lua", "$script", "$in", "$out" },
    description = "Generate $out",
    -- 可选属性
    generator = 1,        -- 标记为生成器规则（修改构建文件本身时使用）
    restat = 1,           -- 重新检查输出时间戳（避免不必要的重建）
    pool = "console",     -- 使用 Ninja 进程池
    deps = "gcc",         -- 依赖风格："gcc" | "msvc"
    depfile = "$out.d",   -- GCC 风格依赖文件
    rspfile = "$out.rsp", -- 响应文件（用于超长命令行）
    rspfile_content = "$in_newline",
}
```

### 属性说明

| 属性 | 说明 |
|------|------|
| `args` | 命令行参数列表（**必需**）。支持 `$in`、`$out`、`$builddir` 等 Ninja 变量，以及 `@path` 语法引用相对路径 |
| `description` | 构建时显示的描述信息 |
| `generator` | 设为 `1` 标记为生成器规则 |
| `restat` | 设为 `1` 启用输出时间戳重新检查 |
| `pool` | Ninja 进程池名称 |
| `deps` | 依赖追踪风格 |
| `depfile` | 依赖文件路径 |
| `rspfile` | 响应文件路径 |
| `rspfile_content` | 响应文件内容 |

---

## lm:build — 自定义构建步骤

使用自定义规则或内联命令执行构建步骤。等同于 Ninja 的 `build` 语句。

### 使用已定义的规则

```lua
lm:rule "protoc" {
    args = { "protoc", "--cpp_out=$builddir/gen", "$in" },
    description = "Protobuf $in",
}

lm:build "gen_proto" {
    rule = "protoc",
    inputs = "proto/*.proto",
    outputs = "$builddir/gen/message.pb.cc",
    deps = "other_target",    -- 可选，依赖其他目标
}
```

### 使用内联命令（不引用规则）

```lua
lm:build "gen_version" {
    args = { "echo", "1.0.0", ">", "$out" },
    inputs = {},
    outputs = "$builddir/version.txt",
}
```

### 匿名构建（不带名称）

```lua
lm:build {
    rule = "protoc",
    inputs = "message.proto",
    outputs = "$builddir/gen/message.pb.cc",
}
```

---

## lm:runlua — 运行 Lua 脚本

在构建过程中运行一个 Lua 脚本，等效于 `luamake lua $script $args`。

```lua
lm:runlua "gen_config" {
    script = "scripts/gen_config.lua",
    args = { "$builddir/config.h", "@data/template.h" },  -- @ 前缀会展开为相对于 rootdir 的绝对路径
    inputs = "data/template.h",
    outputs = "$builddir/config.h",
    deps = "other_target",    -- 可选
}
```

### 匿名 runlua

```lua
lm:runlua {
    script = "scripts/postbuild.lua",
    args = { "$bin" },
    outputs = "$builddir/_/postbuild",  -- 如果不指定 outputs，系统会自动生成
}
```

---

## lm:lua_embed — Lua 嵌入资源

将 Lua 文件（或任意二进制资源）嵌入到 C 源码中，生成一个 `source_set` 供其他目标通过 `deps` 引用。自动导出 `export_includes` 与 `export_objdeps`，依赖方无需再写 `includes` / `objdeps`。

```lua
lm:lua_embed "myembed" {
    bee_glue = true,
    data = {
        main    = { bytecode = true, "src/main.lua" },
        preload = { bytecode = true, { dir = "lualib" } },
        data    = { { file = "assets/config.json", name = "config.json" } },
    },
}

lm:exe "myapp" { deps = "myembed", sources = "src/main.cpp" }
```

关键概念速览：

- 所有条目通过顶层 `data` 的 **组**（group，合法 C 标识符）组织，组名即生成的 `lua_embed_bundle` 结构体字段；
- 每组可独立 `bytecode = true` 嵌入字节码；
- `{ dir, pattern }` 条目指定 `pattern` 时启用 **Lua 模块名扫描**；`bee_glue = true` 时 `preload` 组自动启用；
- `bee_glue = true` 硬约定：必须定义 `main` / `preload` / `data` 三组（可空表），`preload` 注入 `_PRELOAD`、`main[1]` 为入口、`data` 通过 `require "bee.embed"` 暴露。

> **完整规则、`pattern` 语法、字节码版本约束、bee.embed 运行时行为、不使用 `bee_glue` 时的三种自定义接入方式、C API 使用、碰撞处理等**，参见 [`references/advanced/lua_embed.md`](../advanced/lua_embed.md)。

---

## lm:copy — 复制文件

将文件从一个位置复制到另一个位置。`inputs` 和 `outputs` 必须数量一一对应。

```lua
lm:copy "install_headers" {
    inputs = {
        "include/api.h",
        "include/types.h",
    },
    outputs = {
        "$bin/include/api.h",
        "$bin/include/types.h",
    },
    deps = "mylib",    -- 可选，等依赖构建完成后再复制
}
```

---

## lm:phony — 伪目标

创建一个不产生实际文件的目标，用于聚合依赖关系。

### 命名伪目标

```lua
-- 将多个目标聚合为一个
lm:phony "all_libs" {
    deps = { "lib1", "lib2", "lib3" },
}

-- 也可以聚合文件输入
lm:phony "all_headers" {
    inputs = "include/*.h",
    outputs = { "$builddir/headers_ready" },
}
```

### 匿名伪目标

```lua
lm:phony {
    inputs = { "$bin/config.json" },
    outputs = { "config_ready" },
}
```

---

## lm:default — 指定默认构建目标

指定运行 `luamake` 时默认构建的目标。如果不调用此函数，则所有目标都是默认目标。

```lua
lm:default {
    "myapp",
    "mylib",
}
```

仅在主工作区（非 import 的子脚本中）生效。

---

## lm:has — 检查目标是否存在

检查一个目标名称是否已经被定义。

```lua
if not lm:has "optional_lib" then
    lm:lib "optional_lib" {
        sources = "src/fallback.cpp",
    }
end
```

---

## lm:required_version — 要求最低版本

要求 luamake 的最低版本，如果当前版本不满足则报错退出。

```lua
lm:required_version "1.0"
```

---

## lm.pcall / lm.xpcall — 错误处理

luamake 提供了自定义的 `pcall` 和 `xpcall`，在构建脚本中捕获错误时应使用它们而非 Lua 标准库版本。

```lua
local ok, err = lm.pcall(function()
    lm:import "optional/make.lua"
end)
if not ok then
    print("Optional module not found, skipping...")
end
```
