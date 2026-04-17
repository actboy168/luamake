---
name: luamake
description: Luamake 构建系统指南——用于当前项目的 `luamake` / `make.lua` / Ninja 生成流程。当用户需要编写、修改、排查或理解 `make.lua`、目标定义、`lm:conf`、`deps` / `objdeps`、代码生成、Lua C 模块、Bee 运行时集成，或需要解决当前项目中由 `luamake` 驱动的构建问题时，使用此 skill。即使用户没有明确提到 `luamake`，但上下文明显是在处理本项目的构建脚本、构建目录、目标依赖或 `luamake` 生成的 Ninja 流程，也应使用此 skill。不要把它用于纯通用的 C/C++ 编译知识、与本项目无关的 CMake / xmake / Bazel / Meson 问题，或仅讨论编译器理论而未涉及 `luamake` / `make.lua` 的请求。
---
# Luamake Build System

基于 Lua 的构建系统，生成 Ninja 构建文件。

## 快速开始

```lua
local lm = require "luamake"

lm:exe "myapp" {
    sources = { "src/*.c", "!src/test.c" },
    includes = "include",
    defines = { "DEBUG", "VERSION=1.0" },
}
```

```bash
luamake          # 构建
luamake clean    # 清理
luamake rebuild  # 重建
```

---

## 目标类型

| API | 说明 | 输出 |
|-----|------|------|
| `lm:exe` | 可执行文件 | `app.exe` / `app` |
| `lm:dll` | 动态库 | `lib.dll` / `lib.so` / `lib.dylib` |
| `lm:lib` | 静态库 | `lib.lib` / `lib.a` |
| `lm:source_set` | 源码集（不链接，用于复用，通过 `deps` 引用） | 无 |
| `lm:lua_src` | Lua C 模块（静态嵌入到 `lm:lua_exe`） | 无 |
| `lm:lua_dll` | Lua C 模块（动态加载） | `module.dll` / `module.so` |
| `lm:lua_exe` | 内嵌 Lua 的可执行文件 | `app.exe` / `app` |
| `lm:lua_embed` | Lua 嵌入资源（按命名组嵌入 Lua 文件，生成 source_set；自动导出 `includes`/`objdeps`） | 无（source_set） |
| `lm:phony` | 伪目标（聚合依赖） | 无 |

---

## 目标属性

### 源文件

| 属性 | 说明 | 示例 |
|------|------|------|
| `sources` | 源文件 | `"src/*.cpp"`, `{ "a.cpp", "b.cpp" }` |
| `includes` | 包含目录 | `"include"`, `{ "include", "3rd" }` |
| `sysincludes` | 系统包含目录（抑制警告） | `"/usr/local/include"` |
| `defines` | 预处理器定义 | `{ "DEBUG", "VER=1" }` |
| `objdeps` | 对象依赖（编译前必须生成） | `"generated_header"` |

> **`objdeps` 用法**：当源文件依赖代码生成产物（如生成的头文件）时，需用 `objdeps` 声明依赖的目标名，确保生成步骤在编译前完成。`deps` 只控制链接顺序，不能保证编译前生成文件。
> ```lua
> lm:rule "gen_header" { ... }  -- 生成头文件的规则
> lm:exe "app" {
>     sources = "src/*.cpp",
>     objdeps = "gen_header",  -- 编译 src/*.cpp 前先执行 gen_header
> }
> ```
>
> **注意**：`lm:lua_embed` 目标会自动导出 `includes` 和 `objdeps`，通过 `deps` 依赖它的目标无需手动声明这两项。详见下方 `lm:lua_embed` 用法。

### 链接

| 属性 | 说明 | 示例 |
|------|------|------|
| `links` | 链接库 | `{ "pthread", "ws2_32" }` |
| `linkdirs` | 库搜索目录 | `"lib"`, `{ "lib", "/usr/lib" }` |
| `ldflags` | 链接器标志 | `"-Wl,--as-needed"` |
| `frameworks` | macOS/iOS 框架 | `{ "Foundation", "Cocoa" }` |
| `deps` | 目标依赖 | `"lib1"`, `{ "lib1", "lib2" }` |

### 编译

| 属性 | 说明 | 示例 |
|------|------|------|
| `flags` | 编译器标志 | `{ "-Wall", "-O2" }` |
| `cflags` | C 编译器标志 | `"-std=c11"` |
| `cxxflags` | C++ 编译器标志 | `"-std=c++20"` |
| `confs` | 引用命名配置 | `"myconfig"` |

> **注意**：`cflags`/`cxxflags` 直接传递给编译器命令行。在 `lm:conf` 中可用 `c = "c11"` / `cxx = "c++20"` 作为简写，luamake 会自动转换为对应编译器的标准标志（如 MSVC 的 `/std:c11`）。

### 特殊目标用法

**`lm:source_set`** — 将源文件组织为可复用的源码集，通过 `deps` 引用，不单独链接：

```lua
-- 定义共享源码集
lm:source_set "common" {
    includes = "include",
    sources = { "src/common/*.cpp" },
}

-- 多个目标复用同一组源文件
lm:exe "app1" { deps = "common", sources = "src/app1.cpp" }
lm:exe "app2" { deps = "common", sources = "src/app2.cpp" }
```

**`lm:lua_src`** — 将 Lua C 模块静态嵌入到 `lm:lua_exe` 中：

```lua
lm:lua_src "mymodule" {
    sources = "src/mymodule.c",
}

lm:lua_exe "app" {
    deps = "mymodule",
    sources = "src/main.cpp",
}
```

**`lm:lua_embed`** — 将 Lua 文件按命名组嵌入到 C 源码中，生成一个 source_set 供其他目标依赖。`data` 下每个 key 是一个组，组名直接成为生成的 `lua_embed_bundle` 结构体的字段名。每组可独立设置 `bytecode = true`。`bee_glue = true` 启用 bee 胶水层，约定 `data.preload` 注入 `_PRELOAD`、`data.main[1]` 作为入口。自动向依赖方导出 `includes` 和 `objdeps`，通过 `deps` 依赖时无需手动声明。**完整规则（分组语义、`pattern` 语法、字节码取舍、bee_glue 契约、无胶水时的接入姿势）见 `references/advanced/lua_embed.md`**：

```lua
lm:lua_embed "myembed" {
    bee_glue = true,
    data = {
        main    = { bytecode = true, "src/main.lua" },
        preload = { bytecode = true, { dir = "lualib" } },
        data    = { { name = "config.json", file = "assets/config.json" } },
    },
}

lm:lua_src "glue" {
    deps     = "myembed",       -- 自动获取 includes 和 objdeps
    includes = "3rd/bee.lua",
    sources  = "src/glue.cpp",
}
```

lm:lua_exe "app" {
    deps = { "glue", "myembed" },
    sources = "src/main.cpp",
}
```

**`lm:phony`** — 聚合多个目标为一个命名依赖，方便统一引用：

```lua
lm:phony "all_libs" {
    deps = { "libfoo", "libbar", "libqux" },
}

lm:exe "app" {
    deps = "all_libs",
    sources = "main.cpp",
}
```

---

## 配置 (lm:conf)

`lm:conf` 有两种用法，行为完全不同，不要混淆：

### 匿名配置：`lm:conf { ... }` — 立即生效，影响全局

不带名称调用时，属性**立即应用到当前工作区的所有后续目标**，相当于设置全局默认值。

```lua
-- 所有参数均为可选，按项目实际需要填写
lm:conf {
    c = "c11",        -- C 标准："c89", "c99", "c11", "c17"
    cxx = "c++20",    -- C++ 标准："c++11", "c++14", "c++17", "c++20"
    visibility = "hidden",  -- 符号可见性："hidden"（默认隐藏）或 "default"（默认可见）
}

-- 以下目标自动继承上面的配置
lm:exe "app1" { sources = "src/app1.cpp" }
lm:exe "app2" { sources = "src/app2.cpp" }
```

**适用场景**：项目中大部分目标共享相同的编译标准、模式等基础配置时使用。

### 命名配置：`lm:conf "name" { ... }` — 按需引用，不自动生效

带名称调用时，属性**不会立即生效**，仅存储起来，需要目标通过 `confs` 属性显式引用。

```lua
-- 定义命名配置（不会自动应用到任何目标）
lm:conf "mylib" {
    defines = "MYLIB_API",
    includes = "3rd/mylib",
}

-- 通过 confs 引用，只有这个目标会使用该配置
lm:exe "app" {
    confs = "mylib",
    sources = "main.cpp",
}
```

**适用场景**：多个目标需要共享同一组特定配置（如第三方库的头文件路径和宏定义），但不希望污染全局时使用。

### 如何选择

| 场景 | 用法 |
|------|------|
| 设置项目范围的 C/C++ 标准、构建模式等 | `lm:conf { ... }` |
| 为特定的几个目标共享一组 includes/defines | `lm:conf "name" { ... }` + `confs = "name"` |
| 只有一个目标需要特定配置 | 直接写在目标属性里，无需 conf |

---

## 内置变量

### 路径变量

| 变量 | 说明 | 示例 |
|------|------|------|
| `$builddir` | 构建目录（默认 `build`，可自定义） | `build` |
| `$bindir` | 二进制输出目录 | `build/bin` |
| `$objdir` | 对象文件目录 | `build/obj` |
| `$bin` | `$bindir` 别名 | |
| `$obj` | `$objdir` 别名 | |
| `$in` | 输入文件 (规则中) | |
| `$out` | 输出文件 (规则中) | |

> **自定义构建目录**：当项目已使用 `build` 目录时，可在脚本开头修改构建目录：
> ```lua
> lm.builddir = "_build"   -- 构建产物将输出到 _build/ 目录
> ```
> `$bindir` 和 `$objdir` 默认基于 `$builddir`，修改后会自动跟随变化。

### 全局变量

| 变量 | 说明 | 示例值 |
|------|------|--------|
| `lm.os` | 目标 OS | `"windows"`, `"linux"`, `"macos"`, `"ios"`, `"android"` |
| `lm.compiler` | 编译器 | `"msvc"`, `"gcc"`, `"clang"` |
| `lm.arch` | 架构 | `"x86_64"`, `"x86"`, `"arm64"` |
| `lm.mode` | 构建模式 | `"debug"`, `"release"` |
| `lm.workdir` | 工作目录 | 项目根目录 |

---

## 开发工作流

编写或修改 `make.lua` 构建脚本后，**必须**运行构建命令验证脚本的正确性：

```bash
# 1. 运行构建，验证脚本是否有语法错误或配置问题
luamake

# 2. 如果构建失败，根据错误信息修复脚本后重新运行
luamake

# 3. 如果需要从干净状态重建（排除增量构建的干扰）
luamake rebuild
```

### 注意事项

- **Windows 平台**：必须使用 **PowerShell** 运行 `luamake` 命令，不要使用 Git Bash。
- 每次修改 `make.lua` 后都要运行 `luamake` 确认构建成功，不要只写脚本不验证。
- 关注构建输出中的**警告和错误信息**，它们通常指向配置问题（如路径错误、缺少依赖等）。
- 如果构建失败，优先分析错误信息，修复后再次运行验证，直到构建通过。

---

# 最佳实践

| 主题 | 文档 | 包含内容 |
|------|------|----------|
| 依赖管理 | `references/best_practices/bp_dependency.md` | deps 定义顺序、源码集复用、增量源码集、动态模块发现 |
| 条件编译与静态分析 | `references/best_practices/bp_compilation.md` | 条件编译、静态分析集成 |
| 代码生成与 objdeps | `references/best_practices/bp_codegen.md` | 代码生成管道、objdeps 用法 |
| Lua 模块与测试 | `references/best_practices/bp_lua_and_test.md` | Lua C 模块、内置测试框架 |

---

## 详细文档

以下主题的详细资料请参阅当前 skill 中已经提供的 references 目录：

| 主题 | 文档 |
|------|------|
| Bee 运行时库概览 | `references/bee/bee_runtime.md` |
| Bee 文件系统 API | `references/bee/bee_filesystem.md` |
| Bee IO API | `references/bee/bee_io.md` |
| Bee 子进程 API | `references/bee/bee_subprocess.md` |
| Bee Socket API | `references/bee/bee_socket.md` |
| Bee 系统 API | `references/bee/bee_system.md` |
| Bee 线程 API | `references/bee/bee_thread.md` |
| Bee Channel API | `references/bee/bee_channel.md` |
| `lm:lua_embed` 权威参考（分组 / pattern / bytecode / bee_glue / 自定义接入） | `references/advanced/lua_embed.md` |

### 适用边界

优先在以下场景使用本 skill：

- 当前仓库明确使用 `luamake` 或通过 `make.lua` 定义构建目标。
- 用户正在修改 `make.lua`、排查 `luamake` 报错，或理解 `deps`、`objdeps`、`lm:conf`、目标类型、构建目录等机制。
- 用户讨论的问题与当前项目的 Ninja 生成流程、Bee 集成或 Lua C 模块构建直接相关。

以下场景通常不应使用本 skill：

- 与当前项目无关的通用 C/C++ 编译、链接、优化理论问题。
- 纯 `CMake`、`xmake`、`Bazel`、`Meson` 等其他构建系统的问题。
- 只是在问编译器语法、语言标准或平台 API，而没有落到 `luamake` / `make.lua` 的构建脚本上。

---

## 故障排除

| 问题 | 解决方案 |
|------|----------|
| "no source files found" | 检查 glob 模式，确认 `rootdir`，检查文件扩展名 |
| Windows 链接错误 | 添加系统库：`links = { "ws2_32", "iphlpapi", "user32" }` |
| 交叉编译问题 | 使用平台特定配置，检查 `lm.compiler` |
| 缺少生成文件 | 添加 `objdeps` 确保生成后再编译 |
| `build` 目录冲突 | 项目已使用 `build` 目录时，用 `lm.builddir = "_build"` 修改构建目录 |
| 找不到头文件 | 检查 `includes` 路径，使用绝对路径或 `$builddir` |
| Ninja 构建失败 | 删除 `build/` 目录重新构建 |
