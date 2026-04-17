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

当需要将 Lua 脚本或数据文件嵌入到 C/C++ 可执行文件中时，推荐使用 `lm:lua_embed`。它封装了完整的代码生成管道：自动扫描文件 → 生成 C 源码 → 构建 source_set，无需手动编写 `lm:runlua` + `objdeps` 组合。

默认嵌入 Lua **源码**，保证跨 Lua 版本兼容（luamake 宿主 Lua 版本可以与目标 `luaversion` 不同）。如果需要更小的体积或隐藏源码，可在组内设置 `bytecode = true` 嵌入字节码，但此时要求 luamake 宿主 Lua 版本与目标 `luaversion` 一致。

所有文件条目通过顶层 `data` 字段按**组**（任意合法 C 标识符）组织，每个组独立控制 `bytecode` 开关。`{ dir = "..." }` 条目若带 `pattern` 字段则按 Lua 模块名扫描，否则按原始文件名；此外，当 `bee_glue = true` 时，`preload` 组会自动启用 Lua 模块名扫描（因为 `_PRELOAD` 要求模块名作键），无需手写 `pattern`。

### 典型场景：嵌入 Lua 模块到可执行文件

```lua
lm:lua_embed "embedded_lua" {
    data = {
        preload = {
            -- 没有 bee_glue 时，preload 目录必须显式写 pattern，
            -- 否则键名会是 "foo.lua" 而不是模块名 "foo"。
            { dir = "scripts/modules", pattern = "?.lua;?/init.lua" },  -- 按 Lua 模块名扫描
            { file = "scripts/config.lua", name = "config" },          -- 单文件，显式指定名称
        },
        main = {
            "scripts/main.lua",                                           -- 按原始文件名
        },
    },
}

lm:lua_exe "myapp" {
    deps = "embedded_lua",
    sources = "src/main.cpp",
}
```

### 典型场景：使用字节码嵌入（体积更小、隐藏源码）

```lua
lm:lua_embed "embedded_lua" {
    data = {
        preload = {
            bytecode = true,   -- 该组嵌入字节码（需 Lua 版本一致）
            -- 没有 bee_glue 时，preload 目录需显式指定 pattern 才能得到模块名作键。
            { dir = "scripts/modules", pattern = "?.lua;?/init.lua" },
        },
        main = {
            bytecode = true,
            "scripts/main.lua",
        },
    },
}
```

### 典型场景：与 bee.lua 集成

```lua
lm:lua_embed "bee_app" {
    bee_glue = true,           -- 生成 bee.lua 胶水代码（布尔值）
    data = {
        preload = {
            bytecode = true,
            -- bee_glue = true 时，preload 组自动按 Lua 模块名扫描，无需写 pattern。
            { dir = "scripts" },
        },
        main = {
            bytecode = true,
            "src/main.lua",
        },
    },
}

lm:lua_exe "myapp" {
    deps = "bee_app",
    sources = "src/main.cpp",
}
```

### 典型场景：其他目标通过 deps 自动获取 lua_embed 的 includes 和 objdeps

`lm:lua_embed` 会自动导出 `export_includes`（生成的头文件目录，含 `lua_embed_data.h`）和 `export_objdeps`（聚合 `.c` 和 `.h` 两个产物的 phony），其他目标只需通过 `deps` 依赖 `lua_embed` 目标，即可自动获取正确的头文件搜索路径和编译顺序依赖，**无需手动指定 `includes` 和 `objdeps`**。

```lua
-- ✅ 推荐：通过 deps 自动获取 includes 和 objdeps
lm:lua_embed "my_embed" {
    bee_glue = true,
    data = {
        preload = {
            { dir = "lualib" },
        },
    },
}

lm:lua_src "my_glue" {
    deps     = "my_embed",       -- 自动获取 includes 和 objdeps
    includes = "3rd/bee.lua",    -- 只需写自己额外的 includes
    sources  = "src/glue.cpp",   -- glue.cpp 中 #include <lua_embed_data.h>
}
```

> **与手动 `lm:runlua` 的对比**：`lm:lua_embed` 自动处理了 ninja 依赖追踪、`objdeps` 声明、同时生成 `.c` 与 `lua_embed_data.h` 等细节。对于简单的单文件代码生成仍可使用 `lm:runlua`，但批量嵌入 Lua 资源时 `lm:lua_embed` 更简洁可靠。

> **`bytecode` 选项**：每个组独立控制，默认 `false`（嵌入源码），设为 `true` 时使用 `string.dump` 生成字节码嵌入。字节码体积更小且可隐藏源码，但生成的字节码绑定到 luamake 宿主的 Lua 版本，若目标项目通过 `luaversion` 指定了不同版本则会加载失败。
