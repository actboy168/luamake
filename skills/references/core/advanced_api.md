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

将 Lua 文件编译为字节码并嵌入到 C 源码中，生成一个 `source_set` 供其他目标通过 `deps` 引用。支持两种嵌入方式：

- **preload**：Lua 文件编译为字节码，运行时注入 `_PRELOAD` 表，可通过 `require()` 加载
- **data**：文件作为原始字节嵌入，运行时通过 `lua_embed_find()` C API 查找

### 基本用法

```lua
lm:lua_embed "embedded" {
    preload = {
        -- 扫描目录，自动推导模块名
        { dir = "scripts/modules", prefix = "app" },
        -- 单文件指定模块名
        { file = "scripts/init.lua", name = "app.init" },
    },
    data = {
        -- 扫描目录，嵌入所有文件
        { dir = "assets", prefix = "assets/" },
        -- 单文件
        { file = "main.lua", name = "main.lua" },
    },
}

lm:exe "myapp" {
    deps = "embedded",
    sources = "src/main.cpp",
}
```

### 与 bee.lua 集成

设置 `glue = "bee"` 时，额外生成 `bee_glue.c`，提供 `_bee_preload_module()` 和 `_bee_main()` 函数：

```lua
lm:lua_embed "embedded" {
    glue = "bee",
    main = "main.lua",      -- glue="bee" 时必需，指定入口文件（从 data 中查找）
    -- no_main = true,      -- 可选：只生成 _bee_preload_module，不生成 _bee_main
    preload = { ... },
    data = { ... },
}
```

### 属性说明

| 属性 | 类型 | 说明 |
|------|------|------|
| `preload` | table | preload 条目列表 |
| `preload[].dir` | string | 扫描目录路径 |
| `preload[].prefix` | string | 模块名前缀（如 `"app"` → `app.xxx`） |
| `preload[].pattern` | string | 匹配模式（默认 `"?.lua;?/init.lua"`） |
| `preload[].file` | string | 单文件路径（需配合 `name`） |
| `preload[].name` | string | 模块名（`file` 模式必需） |
| `data` | table | data 条目列表 |
| `data[].dir` | string | 扫描目录路径 |
| `data[].prefix` | string | 名称前缀 |
| `data[].file` | string | 单文件路径（需配合 `name`） |
| `data[].name` | string | 查找键名（`file` 模式必需） |
| `glue` | string | 设为 `"bee"` 生成 bee.lua 胶水层 |
| `main` | string | 入口文件名（`glue="bee"` 时必需） |
| `no_main` | boolean | 仅生成 `_bee_preload_module`，不生成 `_bee_main` |

### C API（lua_embed.h）

```c
// 获取所有 preload 条目（NULL 终止数组）
const lua_embed_preload* lua_embed_get_preload(void);

// 按名称查找 data 条目，未找到返回 NULL
const lua_embed_data* lua_embed_find(const char* name);
```

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
