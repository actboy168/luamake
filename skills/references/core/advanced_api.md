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

将 Lua 文件嵌入到 C 源码中，生成一个 `source_set` 供其他目标通过 `deps` 引用。嵌入内容通过 `data` 字段下的**组**（group）组织，每个组名直接成为生成的 `lua_embed_bundle` 结构体的字段名，按字母序排列。

### 基本用法

```lua
lm:lua_embed "myembed" {
    bee_glue = true,
    data = {
        main = {
            bytecode = true,
            "src/main.lua",
        },
        preload = {
            bytecode = true,
            -- bee_glue = true 时，preload 组自动启用 lua 模块名扫描，
            -- 所以这里不需要手写 pattern。
            { dir = "lualib" },
            { file = "scripts/init.lua", name = "init" },
        },
        data = {
            { name = "config.json", file = "assets/config.json" },
            { dir = "assets/data",  prefix = "data/" },
        },
    }
}

lm:exe "myapp" {
    deps = "myembed",
    sources = "src/main.cpp",
}
```

### 组（group）规则

`data` 下每个 string key 为一个组，组名须为合法 C 标识符。每个组是一个 table，包含：

- 可选的 `bytecode = true`：该组独立的字节码开关，嵌入字节码而非源码
- 数组部分（条目列表），每项可以是：
  - 裸字符串：单文件路径，name 取文件名
  - `{ dir=, prefix=, pattern= }`：扫描目录；**有 `pattern` 字段时启用 lua 模块名扫描**（按 `?.lua;?/init.lua` 这种 `?` 占位符语法，`/` 会替换成 `.`，得到 `foo`、`foo.bar` 这样的模块名），否则按原始文件名扫描（键形如 `foo.lua`、`sub/bar.lua`）
  - `{ file=, name= }`：单文件，显式指定名称

> **lua_mode 的启用规则**：
> 1. 组内任一 `dir` 条目带了 `pattern` → 整组切到 lua 模块名扫描；
> 2. `bee_glue = true` 时，`preload` 组自动启用 lua 模块名扫描（因为 `_PRELOAD` 要求模块名作键），条目无需手写 `pattern`，但仍可显式写 `pattern` 来自定义搜索模式；
> 3. 其余情况使用原始文件名扫描。

### 与 bee.lua 集成

设置 `bee_glue = true` 时启用 bee 胶水层，硬编码约定：

- `data.preload` 组自动注入 `_PRELOAD` 表
- `data.main[1]`（第一个条目）作为程序入口

#### bee.embed 模块

启用 `bee_glue` 后，Lua 代码可通过 `require "bee.embed"` 访问 `data.data` 组中的条目。返回的 table 以嵌入文件名为键，索引时按需构造字符串并缓存，重复访问同一键不会重复构造：

```lua
local embed = require "bee.embed"

-- 首次访问：触发构造并缓存
local cfg = embed["config.json"]  -- string 或 nil

-- 再次访问：直接命中缓存，返回同一对象
assert(embed["config.json"] == cfg)
```

Lua 5.5 下使用 `lua_pushexternalstring`，字符串直接引用嵌入数组，零拷贝；低版本回退到 `lua_pushlstring`。

### 属性说明

| 属性 | 类型 | 说明 |
|------|------|------|
| `bee_glue` | bool | 启用 bee 胶水层；约定 `data.preload` 注入 `_PRELOAD`，`data.main[1]` 为入口 |
| `data` | table | 组的集合，string key 为组名（合法 C 标识符），按字母序生成结构体字段 |
| `data.<group>.bytecode` | bool | 该组嵌入字节码而非源码（默认 false） |
| `data.<group>[]` | string | 裸字符串：单文件路径，name 取文件名 |
| `data.<group>[].dir` | string | 扫描目录；有 `pattern` 时按 lua 模块名扫描，否则按原始文件名 |
| `data.<group>[].prefix` | string | 名称前缀 |
| `data.<group>[].pattern` | string | 模块名匹配模式（默认 `"?.lua;?/init.lua"`），有此字段则启用 lua 扫描 |
| `data.<group>[].file` | string | 单文件路径（需配合 `name`） |
| `data.<group>[].name` | string | 条目名（`file` 模式必需） |

### C API（lua_embed_data.h）

生成的结构体字段由组名决定（按字母序）：

```c
#include "lua_embed_data.h"

typedef struct lua_embed_entry {
    const char* name;
    const char* data;
    size_t      size;
} lua_embed_entry;

// 结构体字段由组名决定（按字母序），以下是示例：
typedef struct lua_embed_bundle {
    const lua_embed_entry* data;     /* NULL-terminated */
    const lua_embed_entry* main;     /* NULL-terminated */
    const lua_embed_entry* preload;  /* NULL-terminated */
} lua_embed_bundle;

extern const lua_embed_bundle lua_embed;
```

直接访问全局结构体字段，无需调用函数：

```c
// 遍历 preload 组
const lua_embed_entry* e;
for (e = lua_embed.preload; e->name != NULL; e++) { ... }

// 访问 main 入口（第一个元素）
const lua_embed_entry* m = lua_embed.main;

// 按名查找 data 组
for (e = lua_embed.data; e->name != NULL; e++) {
    if (strcmp(e->name, "config.json") == 0) { ... }
}
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
